import Foundation

/// Parses local Claude Code and Codex logs for daily token usage data.
struct ClaudeLogParser {
    let dataRootURL: URL

    init(claudeDir: URL? = nil) {
        self.dataRootURL = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
    }

    // MARK: - Public

    var claudeDirURL: URL {
        resolveHiddenDirURL(named: ".claude")
    }

    var codexDirURL: URL {
        resolveHiddenDirURL(named: ".codex")
    }

    var hasAnyDataSource: Bool {
        hasClaudeProjectData || hasCodexSessionData
    }

    func parseDailyUsage() -> [Date: DailyUsageData] {
        var result: [Date: DailyUsageData] = [:]
        let calendar = Calendar.current

        merge(parseClaudeUsage(calendar: calendar), into: &result)
        merge(parseCodexUsage(calendar: calendar), into: &result)

        return result
    }

    // MARK: - Claude Code parsing

    private var hasClaudeProjectData: Bool {
        FileManager.default.fileExists(atPath: claudeProjectsDirURL.path)
    }

    private var claudeProjectsDirURL: URL {
        claudeDirURL.appendingPathComponent("projects")
    }

    private func parseClaudeUsage(calendar: Calendar) -> [Date: DailyUsageData] {
        var result: [Date: DailyUsageData] = [:]

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: claudeProjectsDirURL, includingPropertiesForKeys: nil
        ) else { return result }

        for projectDir in projectDirs {
            let jsonlFiles = (try? FileManager.default.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "jsonl" } ?? []

            for file in jsonlFiles {
                parseClaudeSessionFile(file, into: &result, calendar: calendar)
            }
        }

        let messageCounts = parseClaudeHistory(calendar: calendar)
        for (date, count) in messageCounts {
            addUsage(to: &result, date: date, source: .claude, messageCount: count)
        }

        return result
    }

    private func parseClaudeSessionFile(
        _ fileURL: URL,
        into result: inout [Date: DailyUsageData],
        calendar: Calendar
    ) {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        for line in data.split(separator: "\n") where !line.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any],
                  let timestamp = json["timestamp"] as? String else { continue }

            guard let date = parseISO8601(timestamp) else { continue }
            let day = calendar.startOfDay(for: date)

            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
            let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
            let model = message["model"] as? String ?? "unknown"

            addUsage(
                to: &result,
                date: day,
                source: .claude,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheCreation,
                model: model,
                modelTokens: inputTokens + outputTokens,
                apiCallCount: 1
            )
        }
    }

    // MARK: - Claude Code history

    private func parseClaudeHistory(calendar: Calendar) -> [Date: Int] {
        let file = claudeDirURL.appendingPathComponent("history.jsonl")
        guard let data = try? String(contentsOf: file, encoding: .utf8) else { return [:] }

        var counts: [Date: Int] = [:]
        for line in data.split(separator: "\n") where !line.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let timestamp = json["timestamp"] as? Double else { continue }
            let date = Date(timeIntervalSince1970: timestamp / 1000)
            let day = calendar.startOfDay(for: date)
            counts[day, default: 0] += 1
        }
        return counts
    }

    // MARK: - Codex parsing

    private var hasCodexSessionData: Bool {
        FileManager.default.fileExists(atPath: codexSessionsDirURL.path)
    }

    private var codexSessionsDirURL: URL {
        codexDirURL.appendingPathComponent("sessions")
    }

    private func parseCodexUsage(calendar: Calendar) -> [Date: DailyUsageData] {
        var result: [Date: DailyUsageData] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: codexSessionsDirURL,
            includingPropertiesForKeys: nil
        ) else { return result }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            parseCodexSessionFile(fileURL, into: &result, calendar: calendar)
        }

        return result
    }

    private func parseCodexSessionFile(
        _ fileURL: URL,
        into result: inout [Date: DailyUsageData],
        calendar: Calendar
    ) {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return }

        var activeTurnID: String?
        var currentModel = "Codex"
        var latestUsageByTurn: [String: CodexTurnUsage] = [:]

        for line in data.split(separator: "\n") where !line.isEmpty {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let timestamp = json["timestamp"] as? String else { continue }

            switch json["type"] as? String {
            case "turn_context":
                guard let payload = json["payload"] as? [String: Any],
                      let model = payload["model"] as? String else { continue }
                currentModel = model

            case "event_msg":
                guard let payload = json["payload"] as? [String: Any],
                      let eventType = payload["type"] as? String else { continue }

                switch eventType {
                case "task_started":
                    activeTurnID = payload["turn_id"] as? String

                case "token_count":
                    guard let turnID = activeTurnID,
                          let info = payload["info"] as? [String: Any],
                          let lastUsage = info["last_token_usage"] as? [String: Any],
                          let date = parseISO8601(timestamp),
                          let usage = parseCodexTurnUsage(lastUsage, timestamp: date, model: currentModel),
                          usage.totalTokens > 0 else { continue }

                    latestUsageByTurn[turnID] = usage

                default:
                    continue
                }

            default:
                continue
            }
        }

        for usage in latestUsageByTurn.values {
            let day = calendar.startOfDay(for: usage.timestamp)
            addUsage(
                to: &result,
                date: day,
                source: .codex,
                messageCount: 1,
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                model: usage.model,
                modelTokens: usage.totalTokens,
                apiCallCount: 1
            )
        }
    }

    // MARK: - Helpers

    private func addUsage(
        to result: inout [Date: DailyUsageData],
        date: Date,
        source: UsageProvider,
        messageCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        model: String? = nil,
        modelTokens: Int = 0,
        apiCallCount: Int = 0
    ) {
        var daily = result[date, default: DailyUsageData(date: date)]
        daily.addUsage(
            source: source,
            messageCount: messageCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            model: model,
            modelTokens: modelTokens,
            apiCallCount: apiCallCount
        )
        result[date] = daily
    }

    private func merge(_ incoming: [Date: DailyUsageData], into result: inout [Date: DailyUsageData]) {
        for (date, data) in incoming {
            var merged = result[date, default: DailyUsageData(date: date)]
            merged.merge(data)
            result[date] = merged
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

    private func parseCodexTurnUsage(
        _ usage: [String: Any],
        timestamp: Date,
        model: String
    ) -> CodexTurnUsage? {
        let inputTokens = usage["input_tokens"] as? Int ?? 0
        let outputTokens = usage["output_tokens"] as? Int ?? 0
        let reasoningTokens = usage["reasoning_output_tokens"] as? Int ?? 0
        let totalTokens = usage["total_tokens"] as? Int ?? (inputTokens + outputTokens + reasoningTokens)

        guard totalTokens > 0 else { return nil }

        return CodexTurnUsage(
            timestamp: timestamp,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens + reasoningTokens,
            totalTokens: totalTokens
        )
    }

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

private struct CodexTurnUsage {
    let timestamp: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
}

/// Aggregated daily usage from all sources
struct DailyUsageData {
    let date: Date
    var totals = UsageTotals()
    var sourceBreakdown: [UsageProvider: UsageTotals] = [:]

    var totalTokens: Int {
        totals.totalTokens
    }

    mutating func addUsage(
        source: UsageProvider,
        messageCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        model: String? = nil,
        modelTokens: Int = 0,
        apiCallCount: Int = 0
    ) {
        Self.applyUsage(
            to: &totals,
            messageCount: messageCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            model: model,
            modelTokens: modelTokens,
            apiCallCount: apiCallCount
        )

        var sourceTotals = sourceBreakdown[source, default: UsageTotals()]
        Self.applyUsage(
            to: &sourceTotals,
            messageCount: messageCount,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheCreationTokens: cacheCreationTokens,
            model: model,
            modelTokens: modelTokens,
            apiCallCount: apiCallCount
        )
        sourceBreakdown[source] = sourceTotals
    }

    mutating func merge(_ other: DailyUsageData) {
        totals.merge(other.totals)

        for (source, usage) in other.sourceBreakdown {
            var merged = sourceBreakdown[source, default: UsageTotals()]
            merged.merge(usage)
            sourceBreakdown[source] = merged
        }
    }

    func filtered(by filter: UsageSourceFilter) -> TokenUsage? {
        let selectedTotals = filter.provider.flatMap { sourceBreakdown[$0] } ?? totals
        guard selectedTotals.hasUsage else { return nil }

        return TokenUsage(
            date: date,
            totals: selectedTotals,
            sourceBreakdown: sourceBreakdown
        )
    }

    private static func applyUsage(
        to totals: inout UsageTotals,
        messageCount: Int,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        model: String?,
        modelTokens: Int,
        apiCallCount: Int
    ) {
        totals.messageCount += messageCount
        totals.inputTokens += inputTokens
        totals.outputTokens += outputTokens
        totals.cacheReadTokens += cacheReadTokens
        totals.cacheCreationTokens += cacheCreationTokens
        totals.apiCallCount += apiCallCount

        if let model {
            totals.tokensByModel[model, default: 0] += modelTokens
        }
    }
}
