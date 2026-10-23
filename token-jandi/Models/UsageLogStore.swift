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

        for file in signature.files {
            let cached = cache[file.path]
            let parsed: ParsedLogFile
            if let cached, cached.fingerprint == file {
                parsed = cached.parsed
            } else {
                parsed = autoreleasepool { parser.parse(file: file) }
            }
            nextCache[file.path] = CachedFile(fingerprint: file, parsed: parsed)
            report.merge(parsed)
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

    private func invalidateCacheIfTimeZoneChanged(_ identifier: String) {
        if cacheTimeZone != identifier {
            cache.removeAll()
            cacheTimeZone = identifier
        }
    }
}
