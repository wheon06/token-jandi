import Foundation

/// Parses local Claude Code session JSONL files for real token usage data
struct ClaudeLogParser {
    private let claudeDir: URL

    init() {
        self.claudeDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    // MARK: - Public

    func parseDailyUsage() -> [Date: DailyUsageData] {
        var result: [Date: DailyUsageData] = [:]
        let calendar = Calendar.current

        // Parse all session JSONL files under ~/.claude/projects/
        let projectsDir = claudeDir.appendingPathComponent("projects")
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return result }

        for projectDir in projectDirs {
            let jsonlFiles = (try? FileManager.default.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "jsonl" } ?? []

            for file in jsonlFiles {
                parseSessionFile(file, into: &result, calendar: calendar)
            }
        }

        // Also merge message counts from history.jsonl
        let messageCounts = parseHistory(calendar: calendar)
        for (date, count) in messageCounts {
            result[date, default: DailyUsageData(date: date)].messageCount = count
        }

        return result
    }

    // MARK: - Session JSONL parsing

    private func parseSessionFile(
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

            result[day, default: DailyUsageData(date: day)].inputTokens += inputTokens
            result[day, default: DailyUsageData(date: day)].outputTokens += outputTokens
            result[day, default: DailyUsageData(date: day)].cacheReadTokens += cacheRead
            result[day, default: DailyUsageData(date: day)].cacheCreationTokens += cacheCreation
            result[day, default: DailyUsageData(date: day)].tokensByModel[model, default: 0] += (inputTokens + outputTokens)
            result[day, default: DailyUsageData(date: day)].apiCallCount += 1
        }
    }

    // MARK: - history.jsonl (message counts)

    private func parseHistory(calendar: Calendar) -> [Date: Int] {
        let file = claudeDir.appendingPathComponent("history.jsonl")
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

    // MARK: - Helpers

    private func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

/// Aggregated daily usage from all sources
struct DailyUsageData {
    let date: Date
    var messageCount: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var tokensByModel: [String: Int] = [:]
    var apiCallCount: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}
