import Foundation

/// Parses local Claude Code and Codex logs for daily token usage data.
///
/// The parser is stateless: it discovers log files under a data root (normally the
/// user's home folder) and parses one file at a time, so callers can cache results
/// per file and only re-read files whose fingerprint changed.
nonisolated struct UsageLogParser {
    let dataRootURL: URL
    let calendar: Calendar

    init(dataRootURL: URL? = nil, calendar: Calendar = .current) {
        self.dataRootURL = dataRootURL ?? realHomeDirectoryURL()
        self.calendar = calendar
    }

    // MARK: - Locations

    var claudeDirURL: URL {
        resolveHiddenDirURL(named: ".claude")
    }

    var codexDirURL: URL {
        resolveHiddenDirURL(named: ".codex")
    }

    var claudeProjectsDirURL: URL {
        claudeDirURL.appendingPathComponent("projects")
    }

    var codexSessionsDirURL: URL {
        codexDirURL.appendingPathComponent("sessions")
    }

    var hasAnyDataSource: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: claudeProjectsDirURL.path)
            || fileManager.fileExists(atPath: codexSessionsDirURL.path)
    }

    // MARK: - File discovery

    /// Every log file that contributes usage, with the metadata needed to detect changes.
    /// Claude Code stores session logs at `projects/<project>/<session>.jsonl` and
    /// subagent logs at `projects/<project>/<session>/subagents/<agent>.jsonl`, so
    /// both trees are walked recursively.
    func logFiles() -> [LogFileFingerprint] {
        let claudeFiles = jsonlFiles(under: claudeProjectsDirURL).compactMap {
            LogFileFingerprint(url: $0, source: .claude)
        }
        let codexFiles = jsonlFiles(under: codexSessionsDirURL).compactMap {
            LogFileFingerprint(url: $0, source: .codex)
        }
        return (claudeFiles + codexFiles).sorted { $0.path < $1.path }
    }

    func logSignature() -> LogDirectorySignature {
        LogDirectorySignature(files: logFiles())
    }

    // MARK: - Parsing

    /// Parses every log file from scratch. Prefer `UsageLogStore` in the app, which
    /// caches per-file results; this is for one-off use and tests.
    func parseUsageReport() -> UsageParseReport {
        var report = UsageParseReport()
        for file in logFiles() {
            autoreleasepool {
                report.merge(parse(file: file))
            }
        }
        return report
    }

    func parse(file: LogFileFingerprint) -> ParsedLogFile {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: file.path)) else {
            return ParsedLogFile()
        }
        switch file.source {
        case .claude:
            return parseClaudeSession(data)
        case .codex:
            return parseCodexSession(data)
        }
    }

    // MARK: - Claude Code

    /// Claude Code writes one line per content block of an assistant message, and every
    /// line of the same message repeats the same `usage`. Lines are therefore de-duplicated
    /// by `(message.id, requestId)` so each API response is counted once.
    func parseClaudeSession(_ data: Data) -> ParsedLogFile {
        var result = ParsedLogFile()
        var seenMessages = Set<String>()

        forEachJSONLine(in: data) { json in
            guard json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestamp = json["timestamp"] as? String,
                  let date = parseISO8601(timestamp) else { return }

            if let messageID = message["id"] as? String {
                let requestID = json["requestId"] as? String ?? ""
                let key = "\(messageID)|\(requestID)"
                guard seenMessages.insert(key).inserted else { return }
            }

            let totals = UsageTotals(
                inputTokens: intValue(usage["input_tokens"]) ?? 0,
                outputTokens: intValue(usage["output_tokens"]) ?? 0,
                cacheReadTokens: intValue(usage["cache_read_input_tokens"]) ?? 0,
                cacheCreationTokens: intValue(usage["cache_creation_input_tokens"]) ?? 0
            )
            guard totals.hasUsage else { return }

            result.add(totals, source: .claude, on: calendar.startOfDay(for: date))
        }

        return result
    }

    // MARK: - Codex

    /// Codex emits a `token_count` event after each model request. `last_token_usage`
    /// is the per-request delta, which is what gets summed; `total_token_usage` is the
    /// session's running total and only serves as a fallback. A `token_count` whose
    /// `info` is identical to the previous one carries no new request (for example a
    /// rate-limit refresh) and is skipped.
    func parseCodexSession(_ data: Data) -> ParsedLogFile {
        var result = ParsedLogFile()
        var previousInfo: NSDictionary?
        var previousCumulativeTotal = 0

        forEachJSONLine(in: data) { json in
            guard json["type"] as? String == "event_msg",
                  let payload = json["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let timestamp = json["timestamp"] as? String,
                  let date = parseISO8601(timestamp) else { return }

            if let rateLimits = payload["rate_limits"] as? [String: Any] {
                let status = CodexRateLimitStatus(
                    capturedAt: date,
                    planType: rateLimits["plan_type"] as? String,
                    primary: parseCodexRateLimitWindow(rateLimits["primary"]),
                    secondary: parseCodexRateLimitWindow(rateLimits["secondary"]),
                    rateLimitReachedType: rateLimits["rate_limit_reached_type"] as? String
                )
                if let current = result.codexRateLimitStatus, current.capturedAt >= status.capturedAt {
                    // keep the newer one
                } else {
                    result.codexRateLimitStatus = status
                }
            }

            guard let info = payload["info"] as? [String: Any] else { return }
            let infoDictionary = info as NSDictionary
            guard infoDictionary != previousInfo else { return }
            previousInfo = infoDictionary

            let cumulativeTotal = (info["total_token_usage"] as? [String: Any])
                .flatMap { intValue($0["total_tokens"]) }
            defer {
                if let cumulativeTotal {
                    previousCumulativeTotal = cumulativeTotal
                }
            }

            let totals: UsageTotals
            if let last = info["last_token_usage"] as? [String: Any] {
                totals = codexTotals(from: last)
            } else if let cumulativeTotal {
                let delta = max(cumulativeTotal - previousCumulativeTotal, 0)
                totals = UsageTotals(outputTokens: delta)
            } else {
                return
            }

            guard totals.hasUsage else { return }
            result.add(totals, source: .codex, on: calendar.startOfDay(for: date))
        }

        return result
    }

    private func codexTotals(from usage: [String: Any]) -> UsageTotals {
        let inputTokens = intValue(usage["input_tokens"]) ?? 0
        let cachedInputTokens = min(intValue(usage["cached_input_tokens"]) ?? 0, inputTokens)
        let outputTokens = intValue(usage["output_tokens"]) ?? 0
        let totalTokens = intValue(usage["total_tokens"]) ?? (inputTokens + outputTokens)

        return UsageTotals(
            inputTokens: inputTokens - cachedInputTokens,
            outputTokens: max(totalTokens - inputTokens, 0),
            cacheReadTokens: cachedInputTokens
        )
    }

    private func parseCodexRateLimitWindow(_ value: Any?) -> CodexRateLimitWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = doubleValue(dictionary["used_percent"]),
              let windowMinutes = intValue(dictionary["window_minutes"]),
              let resetsAtTimestamp = doubleValue(dictionary["resets_at"]) else { return nil }

        return CodexRateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: Date(timeIntervalSince1970: resetsAtTimestamp)
        )
    }

    // MARK: - Helpers

    private func forEachJSONLine(in data: Data, _ body: ([String: Any]) -> Void) {
        for line in data.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            body(json)
        }
    }

    private func jsonlFiles(under directoryURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let fileURL = item as? URL, fileURL.pathExtension == "jsonl" else { return nil }
            return fileURL
        }
    }

    private func resolveHiddenDirURL(named hiddenDirName: String) -> URL {
        if dataRootURL.lastPathComponent == hiddenDirName {
            return dataRootURL
        }

        let child = dataRootURL.appendingPathComponent(hiddenDirName)
        if FileManager.default.fileExists(atPath: child.path) {
            return child
        }

        let sibling = dataRootURL.deletingLastPathComponent().appendingPathComponent(hiddenDirName)
        if FileManager.default.fileExists(atPath: sibling.path) {
            return sibling
        }

        return child
    }

    private func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardISO8601Formatter = ISO8601DateFormatter()

    private func parseISO8601(_ string: String) -> Date? {
        Self.fractionalISO8601Formatter.date(from: string) ?? Self.standardISO8601Formatter.date(from: string)
    }
}

/// The user's real home folder, even inside the App Sandbox where
/// `FileManager.homeDirectoryForCurrentUser` points at the app container.
nonisolated func realHomeDirectoryURL() -> URL {
    if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: home), isDirectory: true)
    }
    return FileManager.default.homeDirectoryForCurrentUser
}

// MARK: - Results

nonisolated struct ParsedLogFile: Equatable {
    var dailyUsage: [Date: DailyUsageData] = [:]
    var codexRateLimitStatus: CodexRateLimitStatus?

    mutating func add(_ usage: UsageTotals, source: UsageProvider, on day: Date) {
        dailyUsage[day, default: DailyUsageData(date: day)].add(usage, source: source)
    }
}

nonisolated struct UsageParseReport: Equatable {
    var dailyUsage: [Date: DailyUsageData] = [:]
    var codexRateLimitStatus: CodexRateLimitStatus?

    mutating func merge(_ file: ParsedLogFile) {
        mergeDailyUsage(file.dailyUsage, into: &dailyUsage)
        if let status = file.codexRateLimitStatus,
           codexRateLimitStatus.map({ status.capturedAt > $0.capturedAt }) ?? true {
            codexRateLimitStatus = status
        }
    }
}

nonisolated struct LogDirectorySignature: Equatable {
    let files: [LogFileFingerprint]
}

nonisolated struct LogFileFingerprint: Hashable {
    let path: String
    let source: UsageProvider
    let modificationTime: TimeInterval
    let fileSize: Int64

    init(path: String, source: UsageProvider, modificationTime: TimeInterval, fileSize: Int64) {
        self.path = path
        self.source = source
        self.modificationTime = modificationTime
        self.fileSize = fileSize
    }

    init?(url: URL, source: UsageProvider) {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey
        ]), values.isRegularFile != false else { return nil }

        self.init(
            path: url.path,
            source: source,
            modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            fileSize: Int64(values.fileSize ?? 0)
        )
    }
}

nonisolated struct CodexRateLimitStatus: Equatable {
    let capturedAt: Date
    let planType: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let rateLimitReachedType: String?

    var hasLimits: Bool {
        primary != nil || secondary != nil
    }
}

nonisolated struct CodexRateLimitWindow: Equatable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    /// `true` once the window has rolled over, so the recorded percentage is stale.
    func hasReset(at now: Date = Date()) -> Bool {
        resetsAt <= now
    }

    func effectiveUsedPercent(at now: Date = Date()) -> Double {
        hasReset(at: now) ? 0 : usedPercent
    }
}
