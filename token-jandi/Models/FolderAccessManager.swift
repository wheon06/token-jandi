import Foundation
import SwiftUI
import Combine

/// Owns read access to the folder that contains `.claude` and `.codex`.
///
/// Inside the App Sandbox the user has to pick the folder once; a security-scoped
/// bookmark keeps the access across launches. Outside the sandbox the home folder
/// is used directly.
class FolderAccessManager: ObservableObject {
    @Published private(set) var hasAccess = false
    /// The selected data root (preferably the home folder). Both `.claude` and
    /// `.codex` are discovered inside it.
    @Published private(set) var dataRootURL: URL?
    /// `true` when the saved bookmark points to a single data dir (e.g. `~/.claude`)
    /// instead of the home folder, so the UI can prompt re-selection.
    @Published private(set) var needsMigration = false

    private let bookmarkKey = "claudeFolderBookmark"
    private static let hiddenDataDirs: Set<String> = [".claude", ".codex"]
    private var accessedURL: URL?

    private var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    init() {
        if isSandboxed {
            restoreBookmark()
        } else {
            let homeURL = realHomeDirectoryURL()
            let hasData = Self.hiddenDataDirs.contains { name in
                FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(name).path)
            }
            if hasData {
                dataRootURL = homeURL
                hasAccess = true
            }
        }
    }

    deinit {
        stopAccessing()
    }

    /// Path shown in Settings, with the real home folder abbreviated to `~`.
    var displayPath: String {
        guard let path = dataRootURL?.path else { return "~/" }
        let home = realHomeDirectoryURL().path
        if path == home {
            return "~/"
        }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Request access via NSOpenPanel

    func requestFolderAccess(message: String? = nil) {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("folder.select")
        panel.message = message ?? (needsMigration
            ? L("folder.migrationMessage")
            : L("folder.message"))
        panel.directoryURL = realHomeDirectoryURL()
        panel.level = .floating

        panel.begin { [weak self] response in
            guard let self, response == .OK, let selectedURL = panel.url else { return }

            if self.isSandboxed {
                self.saveBookmark(for: selectedURL)
            } else {
                self.stopAccessing()
                self.dataRootURL = selectedURL
                self.hasAccess = true
            }
            self.needsMigration = Self.hiddenDataDirs.contains(selectedURL.lastPathComponent)
        }
    }

    // MARK: - Bookmark persistence (sandbox only)

    private func saveBookmark(for url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            startAccessing(url: url)
        } catch {
            hasAccess = false
        }
    }

    private func restoreBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            // Access has to be active before a replacement bookmark can be created.
            startAccessing(url: url)
            if isStale, let refreshed = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
            }

            // Flag legacy bookmarks that point directly to ~/.claude or ~/.codex
            // so the app can prompt the user to re-select the home folder.
            needsMigration = Self.hiddenDataDirs.contains(url.lastPathComponent)
        } catch {
            hasAccess = false
        }
    }

    private func startAccessing(url: URL) {
        stopAccessing()
        _ = url.startAccessingSecurityScopedResource()
        accessedURL = url
        dataRootURL = url
        hasAccess = true
    }

    private func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
