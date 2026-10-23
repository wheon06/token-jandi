import XCTest
import SQLite3
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
        let window = RateLimitWindow(usedPercent: 80, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1000))
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


    // MARK: - Codex archived sessions (.jsonl.zst)

    func testArchivedCompressedCodexSessionIsParsed() throws {
        let lines = [
            codexTokenCount(at: "2026-03-01T07:00:00.000Z", lastInput: 1000, lastCached: 0, lastOutput: 50, total: 1050),
            codexTokenCount(at: "2026-03-01T08:00:00.000Z", lastInput: 2000, lastCached: 500, lastOutput: 70, total: 3120),
        ]
        let plain = Data((lines.joined(separator: "\n") + "\n").utf8)
        let compressed = try ZstdDecompressor.compress(plain)
        try writeData(compressed, at: archivedDir.appendingPathComponent(
            "rollout-2026-03-01T07-00-00-11111111-2222-3333-4444-555555555555.jsonl.zst"))

        let parser = parser()
        let files = parser.logFiles()
        XCTAssertEqual(files.map(\.kind), [.codexArchivedSession])

        let day = try XCTUnwrap(parser.parseUsageReport().dailyUsage[dayOf("2026-03-01T07:00:00.000Z")])
        XCTAssertEqual(day.sourceBreakdown[.codex]?.totalTokens, 1050 + 2070)
        XCTAssertEqual(day.sourceBreakdown[.codex]?.cacheReadTokens, 500)
    }

    func testJSONLineReaderHandlesLinesSplitAcrossChunks() {
        let text = "{\"a\":1}\n{\"b\":2}\n{\"c\":3}"
        let data = Data(text.utf8)
        var reader = JSONLineReader()
        var seen: [[String: Any]] = []

        // Feed byte by byte so every line crosses a chunk boundary.
        for byte in data {
            reader.feed(Data([byte])) { seen.append($0) }
        }
        reader.finish { seen.append($0) }

        XCTAssertEqual(seen.count, 3)
        XCTAssertEqual(seen.last?["c"] as? Int, 3)
    }

    func testCodexThreadIDIsExtractedFromRolloutFileNames() {
        XCTAssertEqual(
            UsageLogParser.codexThreadID(fromFileName: "rollout-2026-10-20T15-59-28-01A1581B-A281-71F0-939E-7F755D45A6E9.jsonl"),
            "01a1581b-a281-71f0-939e-7f755d45a6e9"
        )
        XCTAssertEqual(
            UsageLogParser.codexThreadID(fromFileName: "rollout-2026-09-16T13-09-43-01a0a868-010d-74d2-b118-b27a8dd10cbd.jsonl.zst"),
            "01a0a868-010d-74d2-b118-b27a8dd10cbd"
        )
        XCTAssertNil(UsageLogParser.codexThreadID(fromFileName: "notes.txt"))
        XCTAssertNil(UsageLogParser.codexThreadID(fromFileName: "short.jsonl"))
    }

    // MARK: - Codex thread database fallback

    func testThreadDatabaseFillsInThreadsWithoutLogFiles() throws {
        let coveredID = "aaaaaaaa-0000-0000-0000-000000000001"
        let missingID = "bbbbbbbb-0000-0000-0000-000000000002"

        try writeCodexSession(name: "rollout-2026-10-20T07-00-00-\(coveredID)", lines: [
            codexTokenCount(at: "2026-10-20T07:00:00.000Z", lastInput: 100, lastCached: 0, lastOutput: 10, total: 110),
        ])
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T05:00:00Z"))
        try writeThreadDatabase(version: 5, rows: [
            (id: coveredID, tokens: 999_999, createdAt: createdAt, archived: 0),
            (id: missingID, tokens: 4_321, createdAt: createdAt, archived: 1),
            (id: "cccccccc-0000-0000-0000-000000000003", tokens: 0, createdAt: createdAt, archived: 0),
        ])

        let parser = parser()
        XCTAssertEqual(parser.logFiles().filter { $0.kind == .codexThreadDatabase }.count, 1)

        let report = parser.parseUsageReport()
        XCTAssertEqual(report.codexDatabaseFallback, CodexDatabaseFallback(threadCount: 1, tokens: 4_321))

        let liveDay = try XCTUnwrap(report.dailyUsage[dayOf("2026-10-20T07:00:00.000Z")])
        XCTAssertEqual(liveDay.totalTokens, 110, "threads that still have a log file must not be double counted")

        let fallbackDay = try XCTUnwrap(report.dailyUsage[calendar.startOfDay(for: createdAt)])
        XCTAssertEqual(fallbackDay.sourceBreakdown[.codex]?.totalTokens, 4_321)
    }

    func testThreadDatabaseURLPicksTheNewestVersion() throws {
        try writeThreadDatabase(version: 3, rows: [])
        try writeThreadDatabase(version: 12, rows: [])
        XCTAssertEqual(parser().codexThreadDatabaseURL?.lastPathComponent, "state_12.sqlite")
    }

    func testStoreUsesDatabaseFallbackAndRefreshesWhenDatabaseChanges() async throws {
        let createdAt = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-01T05:00:00Z"))
        try writeThreadDatabase(version: 5, rows: [
            (id: "dddddddd-0000-0000-0000-000000000004", tokens: 500, createdAt: createdAt, archived: 1),
        ])
        let store = UsageLogStore()

        let firstResult = await store.load(dataRootURL: root, force: false)
        let first = try XCTUnwrap(firstResult)
        XCTAssertEqual(first.report.codexDatabaseFallback?.tokens, 500)

        try writeThreadDatabase(version: 5, rows: [
            (id: "dddddddd-0000-0000-0000-000000000004", tokens: 500, createdAt: createdAt, archived: 1),
            (id: "eeeeeeee-0000-0000-0000-000000000005", tokens: 700, createdAt: createdAt, archived: 1),
        ])
        let secondResult = await store.load(dataRootURL: root, force: false)
        let second = try XCTUnwrap(secondResult)
        XCTAssertEqual(second.report.codexDatabaseFallback, CodexDatabaseFallback(threadCount: 2, tokens: 1_200))
    }


    // MARK: - Claude status line bridge

    private let statusLineJSON = """
    {"model":{"id":"claude-opus-5-5","display_name":"Opus"},
     "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},
                    "seven_day":{"used_percentage":41,"resets_at":1738857600},
                    "spend_limit":{"used_percentage":62.8,"resets_at":1740787200,"used_usd":314.12,"limit_usd":500,"period":"monthly"}}}
    """

    func testStatusLineBridgeParsesClaudeRateLimits() throws {
        let captured = Date(timeIntervalSince1970: 1_738_400_000)
        let status = try XCTUnwrap(ClaudeStatusLineBridge.parse(Data(statusLineJSON.utf8), capturedAt: captured))

        XCTAssertEqual(status.capturedAt, captured)
        XCTAssertEqual(status.fiveHour, RateLimitWindow(usedPercent: 23.5, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)))
        XCTAssertEqual(status.sevenDay?.windowMinutes, 10_080)
        XCTAssertEqual(status.sevenDay?.usedPercent, 41)
        XCTAssertEqual(status.spendLimit?.usedUSD, 314.12)
        XCTAssertEqual(status.spendLimit?.limitUSD, 500)
        XCTAssertEqual(status.spendLimit?.period, "monthly")
    }

    func testStatusLineWithoutRateLimitsIsIgnored() {
        let json = #"{"model":{"id":"claude-opus-5-5"},"context_window":{"used_percentage":12}}"#
        XCTAssertNil(ClaudeStatusLineBridge.parse(Data(json.utf8), capturedAt: Date()))
        XCTAssertNil(ClaudeStatusLineBridge.parse(Data("not json".utf8), capturedAt: Date()))
    }

    func testParserPicksUpTheStatusLineFileWithItsModificationTime() throws {
        let url = root.appendingPathComponent(".claude/token-jandi/statusline.json")
        try writeData(Data(statusLineJSON.utf8), at: url)
        let modified = try XCTUnwrap(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)

        let parser = parser()
        XCTAssertEqual(parser.logFiles().map(\.kind), [.claudeStatusLine])

        let status = try XCTUnwrap(parser.parseUsageReport().claudeRateLimitStatus)
        XCTAssertEqual(status.capturedAt.timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(status.fiveHour?.usedPercent, 23.5)
        XCTAssertTrue(parser.parseUsageReport().dailyUsage.isEmpty, "the bridge file carries no token usage")
    }

    func testInstallerWritesScriptAndRewritesSettingsKeepingThePreviousStatusLine() throws {
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        let marker = root.appendingPathComponent("original-ran.txt")
        let original = """
        {"model":"opus","permissions":{"allow":["Bash(ls)"]},
         "statusLine":{"type":"command","command":"cat > '\(marker.path)'","padding":1}}
        """
        try original.write(to: settingsURL, atomically: true, encoding: .utf8)

        let installer = ClaudeBridgeInstaller(claudeDirURL: claudeDir)
        XCTAssertTrue(installer.isClaudeCodePresent)
        XCTAssertFalse(installer.isInstalled)

        try installer.install()
        XCTAssertTrue(installer.isInstalled)

        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        XCTAssertEqual(settings["model"] as? String, "opus", "unrelated settings survive")
        XCTAssertEqual((settings["permissions"] as? [String: Any])?["allow"] as? [String], ["Bash(ls)"])
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["command"] as? String, installer.scriptURL.path)
        XCTAssertEqual(statusLine["padding"] as? Int, 1, "other statusLine keys are kept")

        let attributes = try FileManager.default.attributesOfItem(atPath: installer.scriptURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? Int).map { $0 & 0o111 }, 0o111, "script is executable")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: installer.bridgeDirectoryURL.path)
            .filter { $0.hasPrefix("settings.json.backup-") }.isEmpty, "settings.json is backed up")

        // Run the installed script like Claude Code would and check both outputs.
        try run(script: installer.scriptURL, stdin: statusLineJSON)
        let status = try XCTUnwrap(parser().parseUsageReport().claudeRateLimitStatus)
        XCTAssertEqual(status.fiveHour?.usedPercent, 23.5)
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), statusLineJSON, "previous status line still receives the JSON")

        // Installing again must not clobber the saved original with our own command.
        try installer.install()
        XCTAssertTrue(try String(contentsOf: installer.originalCommandURL, encoding: .utf8).contains(marker.path))

        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled)
        let restored = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        XCTAssertEqual((restored["statusLine"] as? [String: Any])?["command"] as? String, "cat > '\(marker.path)'")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.originalCommandURL.path))
    }

    func testInstallerWorksWithoutExistingSettingsAndUninstallRemovesTheKey() throws {
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let installer = ClaudeBridgeInstaller(claudeDirURL: claudeDir)

        try installer.install()
        XCTAssertTrue(installer.isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.originalCommandURL.path))

        try run(script: installer.scriptURL, stdin: statusLineJSON)
        XCTAssertNotNil(parser().parseUsageReport().claudeRateLimitStatus)

        try installer.uninstall()
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: installer.settingsURL)) as? [String: Any])
        XCTAssertNil(settings["statusLine"])
    }

    func testInstallerRefusesToTouchUnparseableSettings() throws {
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        try "{ not json".write(to: settingsURL, atomically: true, encoding: .utf8)
        let installer = ClaudeBridgeInstaller(claudeDirURL: claudeDir)

        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? ClaudeBridgeInstaller.InstallError, .settingsUnreadable)
        }
        XCTAssertEqual(try String(contentsOf: settingsURL, encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.scriptURL.path))
    }

    func testInstallerReportsPermissionProblems() throws {
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: claudeDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: claudeDir.path) }

        let installer = ClaudeBridgeInstaller(claudeDirURL: claudeDir)
        XCTAssertThrowsError(try installer.install()) { error in
            XCTAssertEqual(error as? ClaudeBridgeInstaller.InstallError, .permissionDenied)
        }
    }

    private func run(script: URL, stdin input: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["HOME": root.path, "PATH": "/usr/bin:/bin"]
        let pipe = Pipe()
        process.standardInput = pipe
        try process.run()
        pipe.fileHandleForWriting.write(Data(input.utf8))
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
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

    private var archivedDir: URL {
        root.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
    }

    private func writeData(_ data: Data, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    /// Creates a minimal copy of Codex's `threads` table.
    private func writeThreadDatabase(
        version: Int,
        rows: [(id: String, tokens: Int, createdAt: Date, archived: Int)]
    ) throws {
        let dir = root.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("state_\(version).sqlite")
        try? FileManager.default.removeItem(at: url)

        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        guard let db = handle else { return }
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY, rollout_path TEXT NOT NULL, created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, tokens_used INTEGER NOT NULL DEFAULT 0,
            archived INTEGER NOT NULL DEFAULT 0, model TEXT
        );
        """
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, nil), SQLITE_OK)

        for row in rows {
            let created = Int(row.createdAt.timeIntervalSince1970)
            let sql = """
            INSERT INTO threads (id, rollout_path, created_at, updated_at, tokens_used, archived)
            VALUES ('\(row.id)', '/missing/rollout-\(row.id).jsonl', \(created), \(created + 60), \(row.tokens), \(row.archived));
            """
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
    }

    private func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}
