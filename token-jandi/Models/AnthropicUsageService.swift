import Foundation
import SwiftUI
import Combine

struct UsageWindow {
    let utilization: Double  // 0.0 ~ 1.0
    let resetsAt: Date?
}

struct ClaudeUsageData {
    let fiveHour: UsageWindow
    let sevenDay: UsageWindow
    let sevenDaySonnet: UsageWindow
    let isExtraUsageEnabled: Bool
}

enum UsageFetchState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

class AnthropicUsageService: ObservableObject {
    static let shared = AnthropicUsageService()

    @Published var usageData: ClaudeUsageData?
    @Published var fetchState: UsageFetchState = .idle
    @Published private(set) var hasCredentials: Bool = false
    @Published private(set) var resetTimeFormatted: String?

    private var cachedAccessToken: String?
    private var cachedRefreshToken: String?
    private var cachedFileJSON: [String: Any]?
    private var lastFetchedAt: Date?
    private let minFetchInterval: TimeInterval = 30
    private let tokenExpirySeconds = 3600
    private let oauthClientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Computed Usage Values

    var usageRatio: Double {
        usageData?.fiveHour.utilization ?? 0
    }

    var weeklyUsageRatio: Double {
        usageData?.sevenDay.utilization ?? 0
    }

    var usagePercentFormatted: String {
        formatPercent(usageRatio)
    }

    // MARK: - Init

    private init() {
        loadCredentials()
    }

    // MARK: - Credentials

    private static let keychainService = "Claude Code-credentials"

    private var defaultCredentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
    }

    private func resolveCredentialsURL(from claudeDirURL: URL?) -> URL {
        if let claudeDir = claudeDirURL {
            return claudeDir.appendingPathComponent(".credentials.json")
        }
        return defaultCredentialsURL
    }

    func loadCredentials(from claudeDirURL: URL? = nil) {
        // Try Keychain first (modern Claude Code)
        if loadCredentialsFromKeychain() {
            return
        }

        // Fallback to file (legacy)
        let url = resolveCredentialsURL(from: claudeDirURL)

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String
        else {
            hasCredentials = false
            cachedAccessToken = nil
            cachedRefreshToken = nil
            cachedFileJSON = nil
            return
        }

        cachedAccessToken = accessToken
        cachedRefreshToken = oauth["refreshToken"] as? String
        cachedFileJSON = json
        hasCredentials = true
    }

    private func loadCredentialsFromKeychain() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let accessToken = oauth["accessToken"] as? String
        else {
            return false
        }

        cachedAccessToken = accessToken
        cachedRefreshToken = oauth["refreshToken"] as? String
        cachedFileJSON = json
        hasCredentials = true
        return true
    }

    func clearCachedCredentials() {
        cachedAccessToken = nil
        cachedRefreshToken = nil
        cachedFileJSON = nil
        hasCredentials = false
        usageData = nil
        fetchState = .idle
    }

    // MARK: - Token Refresh

    private func refreshAccessToken(completion: @escaping (Bool) -> Void) {
        guard let refreshToken = cachedRefreshToken else {
            completion(false)
            return
        }

        guard let url = URL(string: "https://platform.claude.com/v1/oauth/token") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientId,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String
            else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let newRefreshToken = json["refresh_token"] as? String

            DispatchQueue.main.async {
                self?.cachedAccessToken = newAccessToken
                if let newRefreshToken {
                    self?.cachedRefreshToken = newRefreshToken
                }
                self?.saveCredentials(accessToken: newAccessToken, refreshToken: newRefreshToken ?? refreshToken)
                completion(true)
            }
        }.resume()
    }

    private func saveCredentials(accessToken: String, refreshToken: String) {
        var json = cachedFileJSON ?? [:]

        var oauthDict = (json["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauthDict["accessToken"] = accessToken
        oauthDict["refreshToken"] = refreshToken
        oauthDict["expiresAt"] = Int(Date().timeIntervalSince1970) + tokenExpirySeconds
        json["claudeAiOauth"] = oauthDict

        cachedFileJSON = json

        // Save to Keychain
        if let data = try? JSONSerialization.data(withJSONObject: json) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Self.keychainService,
            ]
            let attrs: [String: Any] = [
                kSecValueData as String: data,
            ]
            let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            if status == errSecItemNotFound {
                var newItem = query
                newItem[kSecValueData as String] = data
                SecItemAdd(newItem as CFDictionary, nil)
            }
        }

        // Also save to file as fallback
        let url = defaultCredentialsURL
        if let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) {
            try? data.write(to: url)
        }
    }

    // MARK: - Fetch Usage

    func fetchUsage(force: Bool = false) {
        guard hasCredentials else {
            fetchState = .error(L("usage.noCredentials"))
            return
        }

        if !force, let lastFetch = lastFetchedAt,
           Date().timeIntervalSince(lastFetch) < minFetchInterval {
            return
        }

        fetchState = .loading
        performFetchUsage(retryOnAuthFailure: true)
    }

    private func performFetchUsage(retryOnAuthFailure: Bool) {
        guard let accessToken = cachedAccessToken else {
            fetchState = .error(L("usage.noCredentials"))
            return
        }

        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else {
            fetchState = .error("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.addValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error {
                    self?.fetchState = .error(error.localizedDescription)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self?.fetchState = .error("No response")
                    return
                }

                // Token expired — try refresh, then reload from Keychain
                if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) && retryOnAuthFailure {
                    self?.refreshAccessToken { success in
                        if success {
                            self?.performFetchUsage(retryOnAuthFailure: false)
                        } else {
                            // Refresh failed — reload from Keychain and retry once
                            self?.loadCredentials()
                            if self?.hasCredentials == true {
                                self?.performFetchUsage(retryOnAuthFailure: false)
                            } else {
                                self?.fetchState = .error(L("usage.authFailed"))
                            }
                        }
                    }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    self?.fetchState = .error("HTTP \(httpResponse.statusCode)")
                    return
                }

                guard let data else {
                    self?.fetchState = .error("No data")
                    return
                }

                self?.parseUsageResponse(data)
                self?.lastFetchedAt = Date()
            }
        }.resume()
    }

    private func parseUsageResponse(_ data: Data) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                fetchState = .error("Parse error")
                return
            }

            func parseWindow(_ key: String) -> UsageWindow {
                guard let window = json[key] as? [String: Any] else {
                    return UsageWindow(utilization: 0, resetsAt: nil)
                }
                let utilization = (window["utilization"] as? Double) ?? 0
                let resetsAt: Date?
                if let resetsAtStr = window["resets_at"] as? String {
                    resetsAt = Self.isoFormatter.date(from: resetsAtStr)
                } else {
                    resetsAt = nil
                }
                return UsageWindow(utilization: utilization / 100.0, resetsAt: resetsAt)
            }

            let extraUsage = json["extra_usage"] as? [String: Any]
            let isExtraEnabled = (extraUsage?["is_enabled"] as? Bool) ?? false

            usageData = ClaudeUsageData(
                fiveHour: parseWindow("five_hour"),
                sevenDay: parseWindow("seven_day"),
                sevenDaySonnet: parseWindow("seven_day_sonnet"),
                isExtraUsageEnabled: isExtraEnabled
            )

            updateResetTimeFormatted()
            fetchState = .loaded
        } catch {
            fetchState = .error("JSON error")
        }
    }

    private func updateResetTimeFormatted() {
        guard let resetsAt = usageData?.fiveHour.resetsAt else {
            resetTimeFormatted = nil
            return
        }
        let remaining = resetsAt.timeIntervalSince(Date())
        guard remaining > 0 else {
            resetTimeFormatted = nil
            return
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        resetTimeFormatted = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
