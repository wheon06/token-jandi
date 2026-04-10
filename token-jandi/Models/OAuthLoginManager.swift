import Foundation
import Combine
import AppKit

enum OAuthLoginState: Equatable {
    case idle
    case loggingIn
    case success
    case failed(String)
}

final class OAuthLoginManager: ObservableObject {
    static let shared = OAuthLoginManager()

    @Published var state: OAuthLoginState = .idle

    private var loginProcess: Process?
    private static var cachedCLIPath: (String, String)?

    private init() {}

    // MARK: - Public

    func startLogin() {
        guard state != .loggingIn else { return }
        state = .loggingIn

        guard let (nodePath, cliPath) = Self.findClaudeCLI() else {
            state = .failed(L("usage.cliNotFound"))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: nodePath)
        process.arguments = [cliPath, "login"]

        let nodeBin = URL(fileURLWithPath: nodePath).deletingLastPathComponent().path
        let currentPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(nodeBin):\(currentPath)"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loginProcess = nil

                AnthropicUsageService.shared.loadCredentials()
                if AnthropicUsageService.shared.hasCredentials {
                    self.completeLoginSuccess()
                } else {
                    self.state = .failed(L("usage.loginFailed"))
                }
            }
        }

        do {
            try process.run()
            loginProcess = process
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func cancelLogin() {
        loginProcess?.terminate()
        loginProcess = nil
        state = .idle
    }

    // MARK: - Logout

    func logout() {
        state = .idle
        AnthropicUsageService.shared.clearCachedCredentials()
    }

    // MARK: - Private

    private func completeLoginSuccess() {
        state = .success
        AnthropicUsageService.shared.fetchUsage(force: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.state == .success {
                self?.state = .idle
            }
        }
    }

    // MARK: - Find Claude CLI

    private static func findClaudeCLI() -> (String, String)? {
        if let cached = cachedCLIPath { return cached }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        // nvm-managed paths
        let nvmBase = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmBase) {
            for version in versions.sorted().reversed() {
                let binDir = "\(nvmBase)/\(version)/bin"
                let nodePath = "\(binDir)/node"
                let cliJs = "\(nvmBase)/\(version)/lib/node_modules/@anthropic-ai/claude-code/cli.js"

                guard fm.isExecutableFile(atPath: nodePath) else { continue }

                if fm.fileExists(atPath: cliJs) {
                    cachedCLIPath = (nodePath, cliJs)
                    return cachedCLIPath
                }

                if let resolved = resolveSymlink("\(binDir)/claude", relativeTo: binDir) {
                    cachedCLIPath = (nodePath, resolved)
                    return cachedCLIPath
                }
            }
        }

        // Homebrew / global install
        let globalCandidates = ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"]
        let nodeCandidates = ["/usr/local/bin/node", "/opt/homebrew/bin/node"]

        for claudePath in globalCandidates {
            guard fm.fileExists(atPath: claudePath) else { continue }
            for nodePath in nodeCandidates {
                guard fm.isExecutableFile(atPath: nodePath) else { continue }
                let cliPath = resolveSymlink(claudePath, relativeTo: URL(fileURLWithPath: claudePath).deletingLastPathComponent().path) ?? claudePath
                cachedCLIPath = (nodePath, cliPath)
                return cachedCLIPath
            }
        }

        return nil
    }

    private static func resolveSymlink(_ path: String, relativeTo baseDir: String) -> String? {
        guard let resolved = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return nil }
        return resolved.hasPrefix("/") ? resolved : "\(baseDir)/\(resolved)"
    }
}
