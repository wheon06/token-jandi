import Foundation
import SwiftUI
import Combine

class FolderAccessManager: ObservableObject {
    @Published var hasAccess = false
    // This stores the selected data root (preferably the home folder) so the app can
    // discover both `.claude` and `.codex` inside it when available.
    @Published var claudeDirectoryURL: URL?

    private let bookmarkKey = "claudeFolderBookmark"

    private var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    init() {
        if isSandboxed {
            restoreBookmark()
        } else {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            let claudeDir = homeURL.appendingPathComponent(".claude")
            let codexDir = homeURL.appendingPathComponent(".codex")

            if FileManager.default.fileExists(atPath: claudeDir.path)
                || FileManager.default.fileExists(atPath: codexDir.path) {
                claudeDirectoryURL = homeURL
                hasAccess = true
            }
        }
    }

    // MARK: - Request access via NSOpenPanel

    func requestFolderAccess() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("folder.select")
        panel.message = needsMigration
            ? L("folder.migrationMessage")
            : L("folder.message")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let selectedURL = panel.url else { return }

            let targetURL = selectedURL

            if self.isSandboxed {
                self.saveBookmark(for: targetURL)
            } else {
                self.claudeDirectoryURL = targetURL
                self.hasAccess = true
            }
            self.needsMigration = false
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

    private static let hiddenDataDirs: Set<String> = [".claude", ".codex"]

    /// `true` when the saved bookmark points to a single data dir (e.g. `~/.claude`)
    /// instead of the home folder, so the UI can prompt re-selection.
    @Published var needsMigration = false

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

            if isStale {
                saveBookmark(for: url)
            } else {
                startAccessing(url: url)
            }

            // Flag legacy bookmarks that point directly to ~/.claude or ~/.codex
            // so the app can prompt the user to re-select the home folder.
            if Self.hiddenDataDirs.contains(url.lastPathComponent) {
                needsMigration = true
            }
        } catch {
            hasAccess = false
        }
    }

    private func startAccessing(url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        claudeDirectoryURL = url
        hasAccess = true
    }

    func stopAccessing() {
        claudeDirectoryURL?.stopAccessingSecurityScopedResource()
    }
}
