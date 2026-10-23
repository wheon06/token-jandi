import Foundation
import Combine

/// UI-facing state for the Claude status line bridge: whether it is installed,
/// and the outcome of the last install or uninstall.
class ClaudeBridgeController: ObservableObject {
    @Published private(set) var isAvailable = false
    @Published private(set) var isInstalled = false
    @Published private(set) var errorMessage: String?

    private let folderAccess: FolderAccessManager
    private var subscriptions = Set<AnyCancellable>()
    /// Set while the folder picker is open because the previous grant was
    /// read-only; the install resumes as soon as a folder is picked.
    private var installAfterFolderPick = false

    init(folderAccess: FolderAccessManager) {
        self.folderAccess = folderAccess
        refresh()

        folderAccess.$dataRootURL
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.installAfterFolderPick {
                    self.installAfterFolderPick = false
                    self.perform(install: true, retryOnPermissionDenied: false)
                } else {
                    self.refresh()
                }
            }
            .store(in: &subscriptions)
    }

    private var installer: ClaudeBridgeInstaller {
        ClaudeBridgeInstaller(claudeDirURL: UsageLogParser(dataRootURL: folderAccess.dataRootURL).claudeDirURL)
    }

    func refresh() {
        let installer = installer
        isAvailable = installer.isClaudeCodePresent
        isInstalled = installer.isInstalled
    }

    func setEnabled(_ enabled: Bool) {
        perform(install: enabled, retryOnPermissionDenied: true)
    }

    private func perform(install: Bool, retryOnPermissionDenied: Bool) {
        errorMessage = nil
        do {
            if install {
                try installer.install()
            } else {
                try installer.uninstall()
            }
        } catch ClaudeBridgeInstaller.InstallError.permissionDenied {
            if install && retryOnPermissionDenied {
                // The folder was picked by an older, read-only version. Ask once
                // more; the picker's message explains why, and the install resumes
                // automatically after the pick.
                installAfterFolderPick = true
                folderAccess.requestFolderAccess(message: L("folder.bridgeMessage"))
            } else {
                errorMessage = L("settings.claudeBridge.permissionDenied")
            }
        } catch ClaudeBridgeInstaller.InstallError.settingsUnreadable {
            errorMessage = L("settings.claudeBridge.settingsUnreadable")
        } catch ClaudeBridgeInstaller.InstallError.writeFailed(let description) {
            errorMessage = description
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
