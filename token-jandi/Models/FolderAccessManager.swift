import Foundation
import SwiftUI
import Combine

class FolderAccessManager: ObservableObject {
    @Published var hasAccess = false
    @Published var claudeDirectoryURL: URL?

    private let bookmarkKey = "claudeFolderBookmark"

    init() {
        restoreBookmark()
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

        // Start at home directory — user just clicks "Select"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        panel.begin { [weak self] response in
            guard response == .OK, let selectedURL = panel.url else { return }

            // Auto-detect .claude folder inside selected directory
            let claudeDir = selectedURL.appendingPathComponent(".claude")
            let targetURL = FileManager.default.fileExists(atPath: claudeDir.path)
                ? claudeDir
                : selectedURL

            self?.saveBookmark(for: targetURL)
        }
    }

    // MARK: - Bookmark persistence

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
