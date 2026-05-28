import Foundation
import SwiftUI
import Combine

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
        didSet { objectWillChange.send() }
    }

    private var resolvedLanguage: String {
        switch selectedLanguage {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ko") ? "ko" : "en"
        case .en, .ko:
            return selectedLanguage.rawValue
        }
    }

    func localized(_ key: String) -> String {
        let lang = resolvedLanguage
        return Self.strings[lang]?[key] ?? Self.strings["en"]?[key] ?? key
    }

    // MARK: - All strings embedded

    private static let strings: [String: [String: String]] = [
        "en": [
            "app.title": "Token Jandi",
            "stats.today": "Today",
            "stats.thisWeek": "This Week",
            "stats.streak": "Streak",
            "stats.total": "Total",
            "stats.messages": "messages",
            "stats.tokens": "tokens",
            "stats.days": "days",
            "source.all": "All",
            "source.claude": "Claude",
            "source.codex": "Codex",
            "codexLimit.title": "Codex limits",
            "codexLimit.primary": "5h limit",
            "codexLimit.secondary": "7d limit",
            "codexLimit.resets": "Resets",
            "heatmap.less": "Less",
            "heatmap.more": "More",
            "heatmap.noUsage": "No usage",
            "detail.messages": "messages",
            "detail.tokens": "tokens",
            "detail.tools": "tools",
            "detail.selectDay": "Hover a cell to see details",
            "day.mon": "Mon",
            "day.wed": "Wed",
            "day.fri": "Fri",
            "chart.daily": "Daily",
            "chart.monthly": "Monthly",
            "action.refresh": "Refresh data",
            "action.quit": "Quit",
            "settings.menuBarUsage": "Show today's usage in menu bar",
            "settings.refreshInterval": "Auto refresh",
            "refresh.off": "Off",
            "settings.language": "Language",
            "settings.version": "Version",
            "settings.author": "Author",
            "settings.source": "Data source",
            "empty.title": "No Claude Code or Codex data found",
            "empty.message": "Select your home folder to start tracking.\nThe app will automatically find .claude and .codex data.",
            "folder.select": "Select",
            "folder.message": "Select your home folder. Token Jandi will automatically find Claude Code and Codex data.",
            "folder.migrationMessage": "To track Codex usage too, please re-select your home folder (~/) instead of ~/.claude.",
            "settings.migrationHint": "Re-select home folder to enable Codex tracking",
            "settings.migrationAction": "Re-select",
            "settings.localDataNotice": "Usage is based only on local files from this Mac, so multi-device account usage may be incomplete.",
            "settings.privacy": "Privacy Policy",
        ],
        "ko": [
            "app.title": "토큰 잔디",
            "stats.today": "오늘",
            "stats.thisWeek": "이번 주",
            "stats.streak": "연속",
            "stats.total": "전체",
            "stats.messages": "메시지",
            "stats.tokens": "토큰",
            "stats.days": "일",
            "source.all": "전체",
            "source.claude": "Claude",
            "source.codex": "Codex",
            "codexLimit.title": "Codex 제한",
            "codexLimit.primary": "5시간 제한",
            "codexLimit.secondary": "7일 제한",
            "codexLimit.resets": "리셋",
            "heatmap.less": "적음",
            "heatmap.more": "많음",
            "heatmap.noUsage": "사용 없음",
            "detail.messages": "메시지",
            "detail.tokens": "토큰",
            "detail.tools": "도구",
            "detail.selectDay": "셀에 마우스를 올려 상세 보기",
            "day.mon": "월",
            "day.wed": "수",
            "day.fri": "금",
            "chart.daily": "일별",
            "chart.monthly": "월별",
            "action.refresh": "데이터 새로고침",
            "action.quit": "종료",
            "settings.menuBarUsage": "메뉴바에 오늘 사용량 표시",
            "settings.refreshInterval": "자동 갱신",
            "refresh.off": "끄기",
            "settings.language": "언어",
            "settings.version": "버전",
            "settings.author": "제작자",
            "settings.source": "데이터 소스",
            "empty.title": "Claude Code 또는 Codex 사용 정보 없음",
            "empty.message": "홈 폴더를 선택하면 자동으로\nClaude Code와 Codex 데이터를 찾습니다.",
            "folder.select": "선택",
            "folder.message": "홈 폴더를 선택해주세요. Token Jandi가 자동으로 Claude Code와 Codex 데이터를 찾습니다.",
            "folder.migrationMessage": "Codex 사용량도 추적하려면 ~/.claude 대신 홈 폴더(~/)를 다시 선택해주세요.",
            "settings.migrationHint": "Codex 추적을 위해 홈 폴더를 다시 선택하세요",
            "settings.migrationAction": "다시 선택",
            "settings.localDataNotice": "사용량은 이 Mac의 로컬 파일 기준이라 여러 기기에서 쓴 계정 사용량은 누락될 수 있습니다.",
            "settings.privacy": "개인정보 처리방침",
        ],
    ]
}
