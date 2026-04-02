import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
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

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @AppStorage("appLanguage") var selectedLanguage: AppLanguage = .system {
        didSet { updateBundle() }
    }

    @Published var bundle: Bundle = Bundle.module

    private init() {
        updateBundle()
    }

    private func updateBundle() {
        let langCode: String
        switch selectedLanguage {
        case .system:
            langCode = Locale.preferredLanguages.first?.components(separatedBy: "-").first ?? "en"
        case .en, .ko:
            langCode = selectedLanguage.rawValue
        }

        if let path = Bundle.module.path(forResource: langCode, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else if let path = Bundle.module.path(forResource: "en", ofType: "lproj"),
                  let fallback = Bundle(path: path) {
            bundle = fallback
        }

        objectWillChange.send()
    }

    func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
