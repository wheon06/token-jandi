import Foundation
import SQLite3

/// One row of Codex's `threads` table in `~/.codex/state_<n>.sqlite`.
nonisolated struct CodexThreadRecord: Equatable {
    let id: String
    let rolloutPath: String
    let createdAt: Date
    let updatedAt: Date
    /// The session's last cumulative `total_token_usage`. It resets on context
    /// compaction, so it is a lower bound for long sessions.
    let tokensUsed: Int
    let archived: Bool
}

/// Read-only access to Codex's thread index. Codex deletes old rollout files
/// from `sessions/` while keeping their token totals here, so the database is
/// the only remaining record for those threads.
nonisolated enum CodexThreadDatabase {
    struct ReadError: Error, CustomStringConvertible {
        let description: String
    }

    /// The newest `state_<n>.sqlite` in the Codex directory, if any.
    static func databaseURL(in codexDirURL: URL) -> URL? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: codexDirURL.path) else { return nil }

        let candidates = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix("state_"), name.hasSuffix(".sqlite"),
                  let version = Int(name.dropFirst("state_".count).dropLast(".sqlite".count)) else { return nil }
            return (version, name)
        }
        guard let newest = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        return codexDirURL.appendingPathComponent(newest.1)
    }

    static func readThreads(at url: URL) throws -> [CodexThreadRecord] {
        // A plain read-only open sees the WAL; `immutable` is the fallback when the
        // sandbox can't take the shared-memory lock.
        var lastError: Error?
        for query in ["mode=ro", "mode=ro&immutable=1"] {
            do {
                return try readThreads(at: url, uriQuery: query)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ReadError(description: "unknown")
    }

    private static func readThreads(at url: URL, uriQuery: String) throws -> [CodexThreadRecord] {
        var encoded = CharacterSet.urlPathAllowed
        encoded.remove("?")
        let path = url.path.addingPercentEncoding(withAllowedCharacters: encoded) ?? url.path
        let uri = "file:\(path)?\(uriQuery)"

        var handle: OpaquePointer?
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw ReadError(description: message)
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, rollout_path, created_at, updated_at, tokens_used, archived
        FROM threads
        WHERE tokens_used > 0
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
            throw ReadError(description: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        var records: [CodexThreadRecord] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw ReadError(description: String(cString: sqlite3_errmsg(db)))
            }

            guard let idText = sqlite3_column_text(stmt, 0) else { continue }
            let rollout = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            records.append(CodexThreadRecord(
                id: String(cString: idText),
                rolloutPath: rollout,
                createdAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 2))),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3))),
                tokensUsed: Int(sqlite3_column_int64(stmt, 4)),
                archived: sqlite3_column_int64(stmt, 5) != 0
            ))
        }
        return records
    }
}
