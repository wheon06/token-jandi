import Foundation
import SwiftUI
import Combine

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case downloading(progress: Double)
    case installing
    case failed(message: String)
}

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    static let currentVersion = "1.0.0"
    static let repoOwner = "wheon06"
    static let repoName = "token-jandi"

    @Published var state: UpdateState = .idle

    private var assetDownloadURL: String?

    private init() {}

    // MARK: - Check

    func checkForUpdates() {
        guard state != .checking else { return }
        state = .checking

        let urlString = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: urlString) else {
            state = .failed(message: "Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    self.state = .failed(message: L("update.checkFailed"))
                    return
                }

                let version = tagName.replacingOccurrences(of: "v", with: "")

                // Find .zip asset
                if let assets = json["assets"] as? [[String: Any]] {
                    self.assetDownloadURL = assets.first(where: {
                        ($0["name"] as? String)?.hasSuffix(".zip") == true
                    })?["browser_download_url"] as? String
                }

                if version.compare(Self.currentVersion, options: .numeric) == .orderedDescending {
                    self.state = .available(version: version)
                } else {
                    self.state = .upToDate
                }
            }
        }.resume()
    }

    // MARK: - Download & Install

    func performUpdate() {
        guard let urlString = assetDownloadURL, let url = URL(string: urlString) else {
            state = .failed(message: L("update.noAsset"))
            return
        }

        state = .downloading(progress: 0)

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self = self else { return }

                guard let tempURL = tempURL, error == nil else {
                    self.state = .failed(message: L("update.downloadFailed"))
                    return
                }

                self.state = .installing
                self.installAndRelaunch(from: tempURL)
            }
        }

        // Observe progress
        let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }

        // Keep observation alive until task completes
        objc_setAssociatedObject(task, "progressObservation", observation, .OBJC_ASSOCIATION_RETAIN)

        task.resume()
    }

    // MARK: - Install

    private func installAndRelaunch(from zipURL: URL) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("TokenJandiUpdate-\(UUID().uuidString)")

        do {
            // Unzip
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-o", zipURL.path, "-d", tempDir.path]
            try unzipProcess.run()
            unzipProcess.waitUntilExit()

            guard unzipProcess.terminationStatus == 0 else {
                state = .failed(message: L("update.unzipFailed"))
                return
            }

            // Find .app in extracted files
            let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            guard let newApp = contents.first(where: { $0.pathExtension == "app" }) else {
                state = .failed(message: L("update.noApp"))
                return
            }

            // Get current app path
            let currentAppPath = Bundle.main.bundlePath
            let currentAppURL = URL(fileURLWithPath: currentAppPath)
            let backupURL = currentAppURL.deletingLastPathComponent()
                .appendingPathComponent("TokenJandi_backup.app")

            // Backup current → Replace → Relaunch
            // Use a shell script so the process survives app termination
            let script = """
            #!/bin/bash
            sleep 1
            rm -rf "\(backupURL.path)"
            mv "\(currentAppURL.path)" "\(backupURL.path)" 2>/dev/null
            cp -R "\(newApp.path)" "\(currentAppURL.path)"
            open "\(currentAppURL.path)"
            rm -rf "\(backupURL.path)"
            rm -rf "\(tempDir.path)"
            """

            let scriptURL = tempDir.appendingPathComponent("update.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptURL.path]
            try chmod.run()
            chmod.waitUntilExit()

            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/bin/bash")
            launcher.arguments = [scriptURL.path]
            try launcher.run()

            // Quit current app
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            state = .failed(message: "\(L("update.installFailed")): \(error.localizedDescription)")
        }
    }
}
