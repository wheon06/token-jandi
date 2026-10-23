import Foundation

/// A rolling rate-limit window (Codex `primary`/`secondary`, Claude `five_hour`/`seven_day`).
nonisolated struct RateLimitWindow: Equatable {
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

/// Claude apps gateway spend limit, when one applies.
nonisolated struct SpendLimitStatus: Equatable {
    let usedPercent: Double
    let resetsAt: Date
    let usedUSD: Double?
    let limitUSD: Double?
    /// `daily`, `weekly` or `monthly`
    let period: String?
}

/// Claude Code rate limits as last reported through the status line bridge.
nonisolated struct ClaudeRateLimitStatus: Equatable {
    let capturedAt: Date
    let fiveHour: RateLimitWindow?
    let sevenDay: RateLimitWindow?
    let spendLimit: SpendLimitStatus?

    var hasLimits: Bool {
        fiveHour != nil || sevenDay != nil || spendLimit != nil
    }
}

/// Claude Code does not log its rate limits anywhere, but it hands them to the
/// status line script as JSON (`rate_limits.five_hour`, `rate_limits.seven_day`,
/// `rate_limits.spend_limit`). A tiny bridge script saves that JSON under
/// `~/.claude/token-jandi/` so the app can show it like the Codex limits.
/// `ClaudeBridgeInstaller` puts the script in place and points Claude Code at it.
nonisolated enum ClaudeStatusLineBridge {
    static let directoryName = "token-jandi"
    static let fileName = "statusline.json"
    static let scriptFileName = "token-jandi-statusline.sh"
    /// The user's previous status line command, run after ours so nothing is lost.
    static let originalCommandFileName = "original-statusline.sh"

    static func directoryURL(in claudeDirURL: URL) -> URL {
        claudeDirURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func fileURL(in claudeDirURL: URL) -> URL {
        directoryURL(in: claudeDirURL).appendingPathComponent(fileName)
    }

    static func parse(_ data: Data, capturedAt: Date) -> ClaudeRateLimitStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rateLimits = json["rate_limits"] as? [String: Any] else { return nil }

        let status = ClaudeRateLimitStatus(
            capturedAt: capturedAt,
            fiveHour: window(rateLimits["five_hour"], minutes: 5 * 60),
            sevenDay: window(rateLimits["seven_day"], minutes: 7 * 24 * 60),
            spendLimit: spendLimit(rateLimits["spend_limit"])
        )
        return status.hasLimits ? status : nil
    }

    private static func window(_ value: Any?, minutes: Int) -> RateLimitWindow? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = ISO8601Parsing.doubleValue(dictionary["used_percentage"]),
              let resetsAt = ISO8601Parsing.doubleValue(dictionary["resets_at"]) else { return nil }

        return RateLimitWindow(
            usedPercent: usedPercent,
            windowMinutes: minutes,
            resetsAt: Date(timeIntervalSince1970: resetsAt)
        )
    }

    private static func spendLimit(_ value: Any?) -> SpendLimitStatus? {
        guard let dictionary = value as? [String: Any],
              let usedPercent = ISO8601Parsing.doubleValue(dictionary["used_percentage"]),
              let resetsAt = ISO8601Parsing.doubleValue(dictionary["resets_at"]) else { return nil }

        return SpendLimitStatus(
            usedPercent: usedPercent,
            resetsAt: Date(timeIntervalSince1970: resetsAt),
            usedUSD: ISO8601Parsing.doubleValue(dictionary["used_usd"]),
            limitUSD: ISO8601Parsing.doubleValue(dictionary["limit_usd"]),
            period: dictionary["period"] as? String
        )
    }

    /// The bridge script, with the bridge directory baked in. Deliberately POSIX
    /// `sh` with no dependencies.
    static func script(bridgeDirectory: String) -> String {
        """
        #!/bin/sh
        # Token Jandi status line bridge for Claude Code. Installed by Token Jandi;
        # turn it off in Token Jandi > Settings > Claude limits to restore the previous status line.
        #
        # Claude Code pipes a JSON object to the status line command after every
        # response. It includes rate_limits (five_hour / seven_day usage and reset
        # times), which Claude Code stores nowhere else. This script saves that JSON
        # for Token Jandi, then forwards it to the previous status line command.

        BRIDGE_DIR='\(shellQuoted(bridgeDirectory))'

        input=$(cat)

        mkdir -p "$BRIDGE_DIR" 2>/dev/null
        if printf '%s' "$input" > "$BRIDGE_DIR/\(fileName).tmp" 2>/dev/null; then
          mv -f "$BRIDGE_DIR/\(fileName).tmp" "$BRIDGE_DIR/\(fileName)" 2>/dev/null
        fi

        if [ -f "$BRIDGE_DIR/\(originalCommandFileName)" ]; then
          printf '%s' "$input" | /bin/sh "$BRIDGE_DIR/\(originalCommandFileName)"
        fi

        """
    }

    /// Escapes a value for use inside single quotes in `sh`.
    static func shellQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }
}

/// Installs the bridge into the user's Claude Code configuration and removes it
/// again: writes the script, saves the previous status line command so it keeps
/// running, backs up `settings.json`, and rewrites its `statusLine`.
nonisolated struct ClaudeBridgeInstaller {
    enum InstallError: Error, Equatable {
        /// `settings.json` exists but isn't a JSON object; nothing was changed.
        case settingsUnreadable
        /// The sandbox grants no write access to the Claude folder.
        case permissionDenied
        case writeFailed(String)
    }

    let claudeDirURL: URL

    var bridgeDirectoryURL: URL { ClaudeStatusLineBridge.directoryURL(in: claudeDirURL) }
    var scriptURL: URL { claudeDirURL.appendingPathComponent(ClaudeStatusLineBridge.scriptFileName) }
    var settingsURL: URL { claudeDirURL.appendingPathComponent("settings.json") }
    var originalCommandURL: URL {
        bridgeDirectoryURL.appendingPathComponent(ClaudeStatusLineBridge.originalCommandFileName)
    }
    var previousStatusLineURL: URL {
        bridgeDirectoryURL.appendingPathComponent("previous-statusline.json")
    }

    /// `true` when Claude Code exists on this Mac at all.
    var isClaudeCodePresent: Bool {
        FileManager.default.fileExists(atPath: claudeDirURL.path)
    }

    /// `true` when `settings.json` points the status line at our script.
    var isInstalled: Bool {
        guard let settings = try? readSettings(),
              let statusLine = settings["statusLine"] as? [String: Any],
              let command = statusLine["command"] as? String else { return false }
        return command.contains(ClaudeStatusLineBridge.scriptFileName)
    }

    func install() throws {
        var settings = try readSettings() ?? [:]
        let fileManager = FileManager.default

        do {
            try fileManager.createDirectory(at: bridgeDirectoryURL, withIntermediateDirectories: true)

            if fileManager.fileExists(atPath: settingsURL.path) {
                let stamp = ISO8601DateFormatter.string(
                    from: Date(), timeZone: .current, formatOptions: [.withFullDate, .withTime, .withTimeZone]
                ).replacingOccurrences(of: ":", with: "-")
                let backupURL = bridgeDirectoryURL.appendingPathComponent("settings.json.backup-\(stamp)")
                try? fileManager.removeItem(at: backupURL)
                try fileManager.copyItem(at: settingsURL, to: backupURL)
            }

            // Keep the previous status line running after ours, unless it is already ours.
            let previous = settings["statusLine"] as? [String: Any]
            if let previous, !isOurs(previous) {
                let encoded = try JSONSerialization.data(withJSONObject: previous, options: [.prettyPrinted, .sortedKeys])
                try encoded.write(to: previousStatusLineURL, options: .atomic)

                if previous["type"] as? String == "command",
                   let command = previous["command"] as? String, !command.isEmpty {
                    try writeExecutable("#!/bin/sh\n\(command)\n", to: originalCommandURL)
                } else {
                    try? fileManager.removeItem(at: originalCommandURL)
                }
            }

            try writeExecutable(ClaudeStatusLineBridge.script(bridgeDirectory: bridgeDirectoryURL.path), to: scriptURL)

            var statusLine = previous ?? [:]
            statusLine["type"] = "command"
            statusLine["command"] = scriptURL.path
            settings["statusLine"] = statusLine
            try writeSettings(settings)
        } catch let error as InstallError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    func uninstall() throws {
        let fileManager = FileManager.default
        do {
            if var settings = try readSettings(),
               let current = settings["statusLine"] as? [String: Any], isOurs(current) {
                if let data = try? Data(contentsOf: previousStatusLineURL),
                   let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    settings["statusLine"] = previous
                } else {
                    settings.removeValue(forKey: "statusLine")
                }
                try writeSettings(settings)
            }

            for url in [scriptURL, originalCommandURL, previousStatusLineURL,
                        ClaudeStatusLineBridge.fileURL(in: claudeDirURL)] {
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
        } catch let error as InstallError {
            throw error
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - Helpers

    private func isOurs(_ statusLine: [String: Any]) -> Bool {
        (statusLine["command"] as? String)?.contains(ClaudeStatusLineBridge.scriptFileName) == true
    }

    /// `nil` when there is no settings file yet.
    private func readSettings() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return nil }
        guard let data = try? Data(contentsOf: settingsURL) else { throw InstallError.permissionDenied }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let settings = object as? [String: Any] else { throw InstallError.settingsUnreadable }
        return settings
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try (data + Data("\n".utf8)).write(to: settingsURL, options: .atomic)
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func map(_ error: Error) -> InstallError {
        let nsError = error as NSError
        let permissionCodes: Set<Int> = [
            NSFileWriteNoPermissionError, NSFileReadNoPermissionError, NSFileWriteVolumeReadOnlyError
        ]
        if nsError.domain == NSCocoaErrorDomain, permissionCodes.contains(nsError.code) {
            return .permissionDenied
        }
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EACCES) || nsError.code == Int(EPERM) {
            return .permissionDenied
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain,
           underlying.code == Int(EACCES) || underlying.code == Int(EPERM) {
            return .permissionDenied
        }
        return .writeFailed(nsError.localizedDescription)
    }
}
