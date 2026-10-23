import XCTest
@testable import token_jandi

final class UsageLogParserTests: XCTestCase {
    private var root: URL!
    private let calendar = Calendar.current

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("token-jandi-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Claude Code

    func testClaudeLinesWithSameMessageAndRequestAreCountedOnce() throws {
        // Claude Code writes one line per content block; all repeat the same usage.
        try writeClaudeSession("session", lines: [
            claudeLine(id: "msg_1", requestID: "req_1", input: 10, output: 5, cacheRead: 100, cacheCreation: 20),
            claudeLine(id: "msg_1", requestID: "req_1", input: 10, output: 5, cacheRead: 100, cacheCreation: 20),
            claudeLine(id: "msg_1", requestID: "req_1", input: 10, output: 5, cacheRead: 100, cacheCreation: 20),
            claudeLine(id: "msg_2", requestID: "req_2", input: 1, output: 1, cacheRead: 0, cacheCreation: 0),
        ])

        let report = parser().parseUsageReport()
        let day = try XCTUnwrap(report.dailyUsage[dayOf("2026-10-20T07:00:00.000Z")])

        XCTAssertEqual(day.totals, UsageTotals(inputTokens: 11, outputTokens: 6, cacheReadTokens: 100, cacheCreationTokens: 20))
        XCTAssertEqual(day.sourceBreakdown[.claude]?.totalTokens, 137)
        XCTAssertNil(day.sourceBreakdown[.codex])
    }

    func testClaudeLinesWithoutMessageIDAreAllCounted() throws {
        try writeClaudeSession("session", lines: [
            claudeLine(id: nil, requestID: nil, input: 3, output: 0, cacheRead: 0, cacheCreation: 0),
            claudeLine(id: nil, requestID: nil, input: 3, output: 0, cacheRead: 0, cacheCreation: 0),
        ])

        let report = parser().parseUsageReport()
        XCTAssertEqual(report.dailyUsage.values.first?.totalTokens, 6)
    }

    func testClaudeSubagentLogsAreIncluded() throws {
        try writeClaudeSession("session", lines: [
            claudeLine(id: "m1", requestID: "r1", input: 10, output: 0, cacheRead: 0, cacheCreation: 0),
        ])
        try writeFile(
            at: claudeProjectDir.appendingPathComponent("session/subagents/agent-1.jsonl"),
            lines: [claudeLine(id: "m2", requestID: "r2", input: 7, output: 0, cacheRead: 0, cacheCreation: 0)]
        )

        let parser = parser()
        XCTAssertEqual(parser.logFiles().count, 2)
        XCTAssertEqual(parser.parseUsageReport().dailyUsage.values.first?.totalTokens, 17)
    }

    func testNonAssistantAndUsageLessLinesAreIgnored() throws {
        try writeClaudeSession("session", lines: [
            #"{"type":"user","timestamp":"2026-10-20T07:00:00.000Z","message":{"role":"user","content":"hi"}}"#,
            #"{"type":"assistant","timestamp":"2026-10-20T07:00:00.000Z","message":{"id":"m","role":"assistant"}}"#,
            "not json at all",
        ])

        XCTAssertTrue(parser().parseUsageReport().dailyUsage.isEmpty)
    }

    // MARK: - Codex

    func testCodexSumsPerRequestDeltasAndMapsCachedInput() throws {
        try writeCodexSession(lines: [
            codexTokenCount(at: "2026-10-20T07:00:44.995Z", lastInput: 41261, lastCached: 0, lastOutput: 149, total: 41410),
            codexTokenCount(at: "2026-10-20T07:00:57.813Z", lastInput: 49332, lastCached: 40960, lastOutput: 139, total: 90881),
        ])

        let report = parser().parseUsageReport()
        let day = try XCTUnwrap(report.dailyUsage[dayOf("2026-10-20T07:00:44.995Z")])
        let codex = try XCTUnwrap(day.sourceBreakdown[.codex])

        XCTAssertEqual(codex.totalTokens, 41410 + 49471)
        XCTAssertEqual(codex.cacheReadTokens, 40960)
        XCTAssertEqual(codex.inputTokens, 41261 + (49332 - 40960))
        XCTAssertEqual(codex.outputTokens, 149 + 139)
    }

    func testCodexRepeatedTokenCountWithIdenticalInfoIsSkipped() throws {
        let event = codexTokenCount(at: "2026-10-20T07:00:44.995Z", lastInput: 100, lastCached: 0, lastOutput: 10, total: 110)
        try writeCodexSession(lines: [event, event])

        XCTAssertEqual(parser().parseUsageReport().dailyUsage.values.first?.totalTokens, 110)
    }

    func testCodexFallsBackToCumulativeDeltaWithoutLastTokenUsage() throws {
        try writeCodexSession(lines: [
            codexCumulativeOnly(at: "2026-10-20T07:00:00.000Z", total: 500),
            codexCumulativeOnly(at: "2026-10-20T07:01:00.000Z", total: 800),
        ])

        XCTAssertEqual(parser().parseUsageReport().dailyUsage.values.first?.totalTokens, 800)
    }

    func testCodexKeepsTheLatestRateLimitStatus() throws {
        try writeCodexSession(name: "a", lines: [
            codexTokenCount(at: "2026-10-20T07:00:00.000Z", lastInput: 1, lastCached: 0, lastOutput: 1, total: 2,
                            primaryUsedPercent: 10, windowMinutes: 10080),
        ])
        try writeCodexSession(name: "b", lines: [
            codexTokenCount(at: "2026-10-21T07:00:00.000Z", lastInput: 1, lastCached: 0, lastOutput: 1, total: 2,
                            primaryUsedPercent: 55, windowMinutes: 300),
        ])

        let status = try XCTUnwrap(parser().parseUsageReport().codexRateLimitStatus)
        XCTAssertEqual(status.primary?.usedPercent, 55)
        XCTAssertEqual(status.primary?.windowMinutes, 300)
        XCTAssertNil(status.secondary)
        XCTAssertEqual(status.planType, "team")
    }

    func testCodexWindowReportsResetOncePast() {
        let window = CodexRateLimitWindow(usedPercent: 80, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(window.hasReset(at: Date(timeIntervalSince1970: 2000)))
        XCTAssertEqual(window.effectiveUsedPercent(at: Date(timeIntervalSince1970: 2000)), 0)
        XCTAssertEqual(window.effectiveUsedPercent(at: Date(timeIntervalSince1970: 500)), 80)
    }

    // MARK: - Store cache

    func testStoreReturnsNilWhenNothingChangedAndReparsesChangedFiles() async throws {
        try writeClaudeSession("session", lines: [
            claudeLine(id: "m1", requestID: "r1", input: 10, output: 0, cacheRead: 0, cacheCreation: 0),
        ])
        let store = UsageLogStore()

        let firstResult = await store.load(dataRootURL: root, force: false)
        let first = try XCTUnwrap(firstResult)
        XCTAssertEqual(first.report.dailyUsage.values.first?.totalTokens, 10)
        XCTAssertTrue(first.hasAnyDataSource)

        let unchanged = await store.load(dataRootURL: root, force: false)
        XCTAssertNil(unchanged)

        let forcedResult = await store.load(dataRootURL: root, force: true)
        let forced = try XCTUnwrap(forcedResult)
        XCTAssertEqual(forced.report, first.report)

        // Appending changes size and mtime, so the file is parsed again.
        try writeClaudeSession("session", lines: [
            claudeLine(id: "m1", requestID: "r1", input: 10, output: 0, cacheRead: 0, cacheCreation: 0),
            claudeLine(id: "m2", requestID: "r2", input: 5, output: 0, cacheRead: 0, cacheCreation: 0),
        ])
        let updatedResult = await store.load(dataRootURL: root, force: false)
        let updated = try XCTUnwrap(updatedResult)
        XCTAssertEqual(updated.report.dailyUsage.values.first?.totalTokens, 15)
    }

    // MARK: - Formatting

    func testFormatTokenCount() {
        XCTAssertEqual(formatTokenCount(0), "0")
        XCTAssertEqual(formatTokenCount(999), "999")
        XCTAssertEqual(formatTokenCount(1_500), "1.5K")
        XCTAssertEqual(formatTokenCount(2_340_000), "2.3M")
    }

    func testUsageLevels() {
        func level(_ tokens: Int) -> Int {
            TokenUsage(date: Date(), totals: UsageTotals(inputTokens: tokens), sourceBreakdown: [:]).level
        }
        XCTAssertEqual(level(0), 0)
        XCTAssertEqual(level(1), 1)
        XCTAssertEqual(level(1_000_000), 1)
        XCTAssertEqual(level(1_000_001), 2)
        XCTAssertEqual(level(10_000_001), 3)
        XCTAssertEqual(level(30_000_001), 4)
    }

    // MARK: - Helpers

    private func parser() -> UsageLogParser {
        UsageLogParser(dataRootURL: root, calendar: calendar)
    }

    private var claudeProjectDir: URL {
        root.appendingPathComponent(".claude/projects/-Users-me-project", isDirectory: true)
    }

    private func dayOf(_ iso: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return calendar.startOfDay(for: try XCTUnwrap(formatter.date(from: iso)))
    }

    private func writeFile(at url: URL, lines: [String]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeClaudeSession(_ name: String, lines: [String]) throws {
        try writeFile(at: claudeProjectDir.appendingPathComponent("\(name).jsonl"), lines: lines)
    }

    private func writeCodexSession(name: String = "rollout", lines: [String]) throws {
        try writeFile(
            at: root.appendingPathComponent(".codex/sessions/2026/10/20/\(name).jsonl"),
            lines: lines
        )
    }

    private func claudeLine(
        id: String?, requestID: String?, input: Int, output: Int, cacheRead: Int, cacheCreation: Int,
        timestamp: String = "2026-10-20T07:00:00.000Z"
    ) -> String {
        var message: [String: Any] = [
            "role": "assistant",
            "model": "claude-opus-5-5",
            "usage": [
                "input_tokens": input,
                "output_tokens": output,
                "cache_read_input_tokens": cacheRead,
                "cache_creation_input_tokens": cacheCreation,
            ],
        ]
        if let id { message["id"] = id }

        var line: [String: Any] = ["type": "assistant", "timestamp": timestamp, "message": message]
        if let requestID { line["requestId"] = requestID }
        return json(line)
    }

    private func codexTokenCount(
        at timestamp: String, lastInput: Int, lastCached: Int, lastOutput: Int, total: Int,
        primaryUsedPercent: Double = 0, windowMinutes: Int = 10080
    ) -> String {
        json([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": ["total_tokens": total],
                    "last_token_usage": [
                        "input_tokens": lastInput,
                        "cached_input_tokens": lastCached,
                        "output_tokens": lastOutput,
                        "total_tokens": lastInput + lastOutput,
                    ],
                ],
                "rate_limits": [
                    "plan_type": "team",
                    "primary": [
                        "used_percent": primaryUsedPercent,
                        "window_minutes": windowMinutes,
                        "resets_at": 1_793_084_434,
                    ],
                    "secondary": NSNull(),
                ],
            ],
        ])
    }

    private func codexCumulativeOnly(at timestamp: String, total: Int) -> String {
        json([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": ["total_token_usage": ["total_tokens": total]],
            ],
        ])
    }

    private func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
