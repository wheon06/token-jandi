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
        panel.message = L("folder.message")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        panel.begin { [weak self] response in
            guard let self = self, response == .OK, let selectedURL = panel.url else { return }

            // Keep the selected folder as the root so sandboxed builds can read
            // both `.claude` and `.codex` when the user selects their home folder.
            let targetURL = selectedURL

            if self.isSandboxed {
                self.saveBookmark(for: targetURL)
            } else {
                self.claudeDirectoryURL = targetURL
                self.hasAccess = true
            }
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

            if isStale {
                saveBookmark(for: url)
            } else {
                startAccessing(url: url)
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
