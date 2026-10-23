import Foundation
import SwiftUI
import Combine

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en = "en"
    case ko = "ko"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .ko: return "한국어"
        }
    }
}

/// Resolves strings from the bundled `Localizable.strings` tables, honoring the
/// in-app language override (which `Bundle.localizedString` can't do on its own).
class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @AppStorage("appLanguage") var selectedLanguage: AppLanguage = .system {
        didSet { objectWillChange.send() }
    }

    private static let fallbackLanguage = "en"
    private var tables: [String: [String: String]] = [:]

    private var resolvedLanguage: String {
        switch selectedLanguage {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? Self.fallbackLanguage
            return preferred.hasPrefix("ko") ? "ko" : Self.fallbackLanguage
        case .en, .ko:
            return selectedLanguage.rawValue
        }
    }

    func localized(_ key: String) -> String {
        table(for: resolvedLanguage)[key]
            ?? table(for: Self.fallbackLanguage)[key]
            ?? key
    }

    private func table(for language: String) -> [String: String] {
        if let cached = tables[language] {
            return cached
        }
        let loaded = Self.loadTable(for: language)
        tables[language] = loaded
        return loaded
    }

    private static func loadTable(for language: String) -> [String: String] {
        guard let url = Bundle.main.url(
            forResource: "Localizable",
            withExtension: "strings",
            subdirectory: nil,
            localization: language
        ), let dictionary = NSDictionary(contentsOf: url) as? [String: String] else {
            return [:]
        }
        return dictionary
    }
}

/// Localization helper. Extra arguments are applied with `String(format:)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = LocalizationManager.shared.localized(key)
    guard !arguments.isEmpty else { return format }
    return String(format: format, arguments: arguments)
}
