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

    /// Codex compresses old rollouts into `archived_sessions/*.jsonl.zst`.
    var codexArchivedSessionsDirURL: URL {
        codexDirURL.appendingPathComponent("archived_sessions")
    }

    var codexThreadDatabaseURL: URL? {
        CodexThreadDatabase.databaseURL(in: codexDirURL)
    }

    /// Written by the status line bridge script; see `ClaudeStatusLineBridge`.
    var claudeStatusLineURL: URL {
        ClaudeStatusLineBridge.fileURL(in: claudeDirURL)
    }

    var hasAnyDataSource: Bool {
        let fileManager = FileManager.default
        return fileManager.fileExists(atPath: claudeProjectsDirURL.path)
            || fileManager.fileExists(atPath: codexSessionsDirURL.path)
            || fileManager.fileExists(atPath: codexArchivedSessionsDirURL.path)
            || codexThreadDatabaseURL != nil
    }

    // MARK: - File discovery

    /// Every log file that contributes usage, with the metadata needed to detect changes.
    /// Claude Code stores session logs at `projects/<project>/<session>.jsonl` and
    /// subagent logs at `projects/<project>/<session>/subagents/<agent>.jsonl`, so
    /// both trees are walked recursively.
    func logFiles() -> [LogFileFingerprint] {
        var files: [LogFileFingerprint] = []

        files += jsonlFiles(under: claudeProjectsDirURL).compactMap {
            LogFileFingerprint(url: $0, kind: .claudeSession)
        }
        files += jsonlFiles(under: codexSessionsDirURL).compactMap {
            LogFileFingerprint(url: $0, kind: .codexSession)
        }
        files += archivedCodexFiles().compactMap {
            LogFileFingerprint(url: $0, kind: .codexArchivedSession)
        }
        if let databaseURL = codexThreadDatabaseURL,
           let fingerprint = LogFileFingerprint(databaseURL: databaseURL) {
            files.append(fingerprint)
        }
        if let statusLine = LogFileFingerprint(url: claudeStatusLineURL, kind: .claudeStatusLine) {
            files.append(statusLine)
        }

        return files.sorted { $0.path < $1.path }
    }

    func logSignature() -> LogDirectorySignature {
        LogDirectorySignature(files: logFiles())
    }

    // MARK: - Parsing

    /// Parses every log file from scratch. Prefer `UsageLogStore` in the app, which
    /// caches per-file results; this is for one-off use and tests.
    func parseUsageReport() -> UsageParseReport {
        var report = UsageParseReport()
        let files = logFiles()

        for file in files where file.kind != .codexThreadDatabase {
            autoreleasepool {
                report.merge(parse(file: file))
            }
        }

        if let database = files.first(where: { $0.kind == .codexThreadDatabase }) {
            let covered = Self.codexThreadIDs(coveredBy: files)
            report.merge(parseCodexThreadDatabase(database, excludingThreadIDs: covered))
        }

        return report
    }

    func parse(file: LogFileFingerprint) -> ParsedLogFile {
        let url = URL(fileURLWithPath: file.path)
        switch file.kind {
        case .claudeSession:
            guard let data = try? Data(contentsOf: url) else { return ParsedLogFile() }
            return parseClaudeSession(data)
        case .codexSession:
            guard let data = try? Data(contentsOf: url) else { return ParsedLogFile() }
            return parseCodexSession(data)
        case .codexArchivedSession:
            if url.pathExtension == "zst" {
                return parseCompressedCodexSession(at: url)
            }
            guard let data = try? Data(contentsOf: url) else { return ParsedLogFile() }
            return parseCodexSession(data)
        case .claudeStatusLine:
            guard let data = try? Data(contentsOf: url) else { return ParsedLogFile() }
            var result = ParsedLogFile()
            result.claudeRateLimitStatus = ClaudeStatusLineBridge.parse(
                data,
                capturedAt: Date(timeIntervalSince1970: file.modificationTime)
            )
            return result
        case .codexThreadDatabase:
            // Needs the set of threads covered by log files; see parseCodexThreadDatabase.
            return ParsedLogFile()
        }
    }

    // MARK: - Claude Code

    /// Claude Code writes one line per content block of an assistant message, and every
    /// line of the same message repeats the same `usage`. Lines are therefore de-duplicated
    /// by `(message.id, requestId)` so each API response is counted once.
    func parseClaudeSession(_ data: Data) -> ParsedLogFile {
        var result = ParsedLogFile()
        var seenMessages = Set<String>()

        var reader = JSONLineReader()
        let handle: ([String: Any]) -> Void = { json in
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
        reader.feed(data, handle)
        reader.finish(handle)

        return result
    }

    // MARK: - Codex

    func parseCodexSession(_ data: Data) -> ParsedLogFile {
        var session = CodexSessionParser(calendar: calendar)
        var reader = JSONLineReader()
        reader.feed(data) { session.consume($0) }
        reader.finish { session.consume($0) }
        return session.result
    }

    func parseCompressedCodexSession(at url: URL) -> ParsedLogFile {
        var session = CodexSessionParser(calendar: calendar)
        var reader = JSONLineReader()
        do {
            try ZstdDecompressor.decompress(fileAt: url) { chunk in
                reader.feed(chunk) { session.consume($0) }
            }
        } catch {
            // Keep whatever decoded before the error; a truncated archive still
            // holds valid earlier events.
        }
        reader.finish { session.consume($0) }
        return session.result
    }

    /// Threads whose rollout file is gone from disk only survive as a row in Codex's
    /// thread database. Their `tokens_used` is attributed to the day the thread was
    /// created and flagged as an estimate in the report.
    func parseCodexThreadDatabase(
        _ file: LogFileFingerprint,
        excludingThreadIDs covered: Set<String>
    ) -> ParsedLogFile {
        var result = ParsedLogFile()
        guard let threads = try? CodexThreadDatabase.readThreads(at: URL(fileURLWithPath: file.path)) else {
            return result
        }

        var fallback = CodexDatabaseFallback()
        for thread in threads where !covered.contains(thread.id.lowercased()) {
            result.add(
                UsageTotals(inputTokens: thread.tokensUsed),
                source: .codex,
                on: calendar.startOfDay(for: thread.createdAt)
            )
            fallback.threadCount += 1
            fallback.tokens += thread.tokensUsed
        }

        if fallback.threadCount > 0 {
            result.codexDatabaseFallback = fallback
        }
        return result
    }

    /// Thread IDs of every Codex rollout among `files`, live or archived.
    static func codexThreadIDs(coveredBy files: [LogFileFingerprint]) -> Set<String> {
        Set(files.compactMap { file in
            guard file.kind == .codexSession || file.kind == .codexArchivedSession else { return nil }
            return codexThreadID(fromFileName: (file.path as NSString).lastPathComponent)
        })
    }

    /// `rollout-2026-10-20T15-59-28-<uuid>.jsonl[.zst]` → `<uuid>`
    static func codexThreadID(fromFileName fileName: String) -> String? {
        var name = fileName.lowercased()
        if name.hasSuffix(".zst") { name.removeLast(4) }
        guard name.hasSuffix(".jsonl") else { return nil }
        name.removeLast(6)

        guard name.count >= 36 else { return nil }
        let candidate = String(name.suffix(36))
        return UUID(uuidString: candidate) != nil ? candidate : nil
    }

    // MARK: - Helpers

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

    private func archivedCodexFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: codexArchivedSessionsDirURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { item in
            guard let fileURL = item as? URL else { return nil }
            let name = fileURL.lastPathComponent
            return name.hasSuffix(".jsonl.zst") || name.hasSuffix(".jsonl") ? fileURL : nil
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

    private func parseISO8601(_ string: String) -> Date? {
        ISO8601Parsing.date(from: string)
    }

    private func intValue(_ value: Any?) -> Int? {
        ISO8601Parsing.intValue(value)
    }
}

/// Incremental Codex rollout parser. Codex emits a `token_count` event after each
/// model request. `last_token_usage` is the per-request delta, which is what gets
/// summed; `total_token_usage` is the session's running total and only serves as a
/// fallback. A `token_count` whose `info` is identical to the previous one carries no
/// new request (for example a rate-limit refresh) and is skipped.
nonisolated struct CodexSessionParser {
    let calendar: Calendar
    private(set) var result = ParsedLogFile()
    private var previousInfo: NSDictionary?
    private var previousCumulativeTotal = 0

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    mutating func consume(_ json: [String: Any]) {
        guard json["type"] as? String == "event_msg",
              let payload = json["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let timestamp = json["timestamp"] as? String,
              let date = ISO8601Parsing.date(from: timestamp) else { return }

        if let rateLimits = payload["rate_limits"] as? [String: Any] {
            let status = CodexRateLimitStatus(
                capturedAt: date,
                planType: rateLimits["plan_type"] as? String,
                primary: Self.parseWindow(rateLimits["primary"]),
                secondary: Self.parseWindow(rateLimits["secondary"]),
                rateLimitReachedType: rateLimits["rate_limit_reached_type"] as? String
            )
            if result.codexRateLimitStatus.map({ status.capturedAt > $0.capturedAt }) ?? true {
                result.codexRateLimitStatus = status
            }
        }

        guard let info = payload["info"] as? [String: Any] else { return }
        let infoDictionary = info as NSDictionary
        guard infoDictionary != previousInfo else { return }
        previousInfo = infoDictionary

        let cumulativeTotal = (info["total_token_usage"] as? [String: Any])
            .flatMap { ISO8601Parsing.intValue($0["total_tokens"]) }
        defer {
            if let cumulativeTotal {
                previousCumulativeTotal = cumulativeTotal
            }
        }

        let totals: UsageTotals
        if let last = info["last_token_usage"] as? [String: Any] {
            totals = Self.totals(from: last)
        } else if let cumulativeTotal {
            totals = UsageTotals(outputTokens: max(cumulativeTotal - previousCumulativeTotal, 0))
        } else {
            return
        }

        guard totals.hasUsage else { return }
        result.add(totals, source: .codex, on: calendar.startOfDay(for: date))
    }

    private static func totals(from usage: [String: Any]) -> UsageTotals {
        let inputTokens = ISO8601Parsing.intValue(usage["input_tokens"]) ?? 0
        let cachedInputTokens = min(ISO8601Parsing.intValue(usage["cached_input_tokens"]) ?? 0, inputTokens)
        let outputTokens = ISO8601Parsing.intValue(usage["output_tokens"]) ?? 0
        let totalTokens = ISO8601Parsing.intValue(usage["total_tokens"]) ?? (inputTokens + outputTokens)

        return UsageTotals(
            inputTokens: inputTokens - cachedInputTokens,
            outputTokens: max(totalTokens - inputTokens, 0),
            cacheReadTokens: cachedInputTokens
        )
    }

    private static func parseWindow(_ value: Any?) -> RateLimitWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = ISO8601Parsing.doubleValue(dictionary["used_percent"]),
              let windowMinutes = ISO8601Parsing.intValue(dictionary["window_minutes"]),
              let resetsAtTimestamp = ISO8601Parsing.doubleValue(dictionary["resets_at"]) else { return nil }

        return RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: windowMinutes,
            resetsAt: Date(timeIntervalSince1970: resetsAtTimestamp)
        )
    }
}

/// Shared scalar decoding for the JSON logs.
nonisolated enum ISO8601Parsing {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter = ISO8601DateFormatter()

    static func date(from string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
    }

    static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        return nil
    }

    static func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double {
            return double
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
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
    var claudeRateLimitStatus: ClaudeRateLimitStatus?
    var codexDatabaseFallback: CodexDatabaseFallback?

    mutating func add(_ usage: UsageTotals, source: UsageProvider, on day: Date) {
        dailyUsage[day, default: DailyUsageData(date: day)].add(usage, source: source)
    }
}

/// Codex threads counted from the thread database because their log file is gone.
nonisolated struct CodexDatabaseFallback: Equatable {
    var threadCount = 0
    var tokens = 0
}

nonisolated struct UsageParseReport: Equatable {
    var dailyUsage: [Date: DailyUsageData] = [:]
    var codexRateLimitStatus: CodexRateLimitStatus?
    var claudeRateLimitStatus: ClaudeRateLimitStatus?
    var codexDatabaseFallback: CodexDatabaseFallback?

    mutating func merge(_ file: ParsedLogFile) {
        mergeDailyUsage(file.dailyUsage, into: &dailyUsage)
        if let status = file.codexRateLimitStatus,
           codexRateLimitStatus.map({ status.capturedAt > $0.capturedAt }) ?? true {
            codexRateLimitStatus = status
        }
        if let status = file.claudeRateLimitStatus,
           claudeRateLimitStatus.map({ status.capturedAt > $0.capturedAt }) ?? true {
            claudeRateLimitStatus = status
        }
        if let fallback = file.codexDatabaseFallback {
            var merged = codexDatabaseFallback ?? CodexDatabaseFallback()
            merged.threadCount += fallback.threadCount
            merged.tokens += fallback.tokens
            codexDatabaseFallback = merged
        }
    }
}

nonisolated struct LogDirectorySignature: Equatable {
    let files: [LogFileFingerprint]
}

nonisolated enum LogFileKind: Hashable {
    case claudeSession
    case claudeStatusLine
    case codexSession
    case codexArchivedSession
    case codexThreadDatabase

    var source: UsageProvider {
        switch self {
        case .claudeSession, .claudeStatusLine: return .claude
        case .codexSession, .codexArchivedSession, .codexThreadDatabase: return .codex
        }
    }
}

nonisolated struct LogFileFingerprint: Hashable {
    let path: String
    let kind: LogFileKind
    let modificationTime: TimeInterval
    let fileSize: Int64

    var source: UsageProvider { kind.source }

    init(path: String, kind: LogFileKind, modificationTime: TimeInterval, fileSize: Int64) {
        self.path = path
        self.kind = kind
        self.modificationTime = modificationTime
        self.fileSize = fileSize
    }

    init?(url: URL, kind: LogFileKind) {
        guard let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .fileSizeKey, .isRegularFileKey
        ]), values.isRegularFile != false else { return nil }

        self.init(
            path: url.path,
            kind: kind,
            modificationTime: values.contentModificationDate?.timeIntervalSince1970 ?? 0,
            fileSize: Int64(values.fileSize ?? 0)
        )
    }

    /// SQLite in WAL mode appends to `<db>-wal` long before the main file changes,
    /// so both files feed the fingerprint.
    init?(databaseURL: URL) {
        guard let main = LogFileFingerprint(url: databaseURL, kind: .codexThreadDatabase) else { return nil }
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let wal = LogFileFingerprint(url: walURL, kind: .codexThreadDatabase)

        self.init(
            path: databaseURL.path,
            kind: .codexThreadDatabase,
            modificationTime: max(main.modificationTime, wal?.modificationTime ?? 0),
            fileSize: main.fileSize + (wal?.fileSize ?? 0)
        )
    }
}

nonisolated struct CodexRateLimitStatus: Equatable {
    let capturedAt: Date
    let planType: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
    let rateLimitReachedType: String?

    var hasLimits: Bool {
        primary != nil || secondary != nil
    }
}

