import Foundation

/// Loads usage off the main actor and caches parsed results per log file, so a
/// refresh only re-reads files whose size or modification time changed.
actor UsageLogStore {
    struct Snapshot: Equatable {
        let report: UsageParseReport
        let hasAnyDataSource: Bool
        let signature: LogDirectorySignature
        let day: Date
    }

    private struct CachedFile {
        let fingerprint: LogFileFingerprint
        let parsed: ParsedLogFile
    }

    private var cache: [String: CachedFile] = [:]
    private var cacheTimeZone: String?
    private var lastSnapshot: Snapshot?

    /// Returns a fresh snapshot, or `nil` when nothing changed since the last one
    /// (same files, same day) and `force` is false.
    func load(dataRootURL: URL?, force: Bool, now: Date = Date()) -> Snapshot? {
        let calendar = Calendar.current
        let parser = UsageLogParser(dataRootURL: dataRootURL, calendar: calendar)
        let signature = parser.logSignature()
        let day = calendar.startOfDay(for: now)

        if !force, let last = lastSnapshot, last.signature == signature, last.day == day {
            return nil
        }

        invalidateCacheIfTimeZoneChanged(calendar.timeZone.identifier)

        var report = UsageParseReport()
        var nextCache: [String: CachedFile] = [:]
        var filesToParse: [LogFileFingerprint] = []

        for file in signature.files where file.kind != .codexThreadDatabase {
            if let cached = cache[file.path], cached.fingerprint == file {
                nextCache[file.path] = cached
            } else {
                filesToParse.append(file)
            }
        }

        // Files are independent, so new or changed ones are parsed in parallel. The
        // first load after install (hundreds of archived Codex sessions) is the case
        // that benefits; a routine refresh usually touches one or two files.
        for (file, parsed) in Self.parseConcurrently(filesToParse, with: parser) {
            nextCache[file.path] = CachedFile(fingerprint: file, parsed: parsed)
        }

        for file in signature.files where file.kind != .codexThreadDatabase {
            if let cached = nextCache[file.path] {
                report.merge(cached.parsed)
            }
        }

        // The thread database fills in Codex threads whose rollout file no longer
        // exists. Which threads those are depends on the file list, so it is not
        // cached per file; the query itself is cheap.
        if let database = signature.files.first(where: { $0.kind == .codexThreadDatabase }) {
            let covered = UsageLogParser.codexThreadIDs(coveredBy: signature.files)
            report.merge(parser.parseCodexThreadDatabase(database, excludingThreadIDs: covered))
        }

        cache = nextCache

        let snapshot = Snapshot(
            report: report,
            hasAnyDataSource: parser.hasAnyDataSource,
            signature: signature,
            day: day
        )
        lastSnapshot = snapshot
        return snapshot
    }

    private static func parseConcurrently(
        _ files: [LogFileFingerprint],
        with parser: UsageLogParser
    ) -> [(LogFileFingerprint, ParsedLogFile)] {
        guard !files.isEmpty else { return [] }

        let lock = NSLock()
        var results = [ParsedLogFile?](repeating: nil, count: files.count)

        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let parsed = autoreleasepool { parser.parse(file: files[index]) }
            lock.lock()
            results[index] = parsed
            lock.unlock()
        }

        return zip(files, results).map { ($0, $1 ?? ParsedLogFile()) }
    }

    private func invalidateCacheIfTimeZoneChanged(_ identifier: String) {
        if cacheTimeZone != identifier {
            cache.removeAll()
            cacheTimeZone = identifier
        }
    }
}
