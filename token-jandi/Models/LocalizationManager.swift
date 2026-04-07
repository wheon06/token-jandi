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
            "settings.update": "Update",
            "settings.checkUpdate": "Check for updates",
            "settings.updateAvailable": "available",
            "update.checking": "Checking...",
            "update.upToDate": "Up to date",
            "update.checkFailed": "Check failed",
            "update.noAsset": "No download found",
            "update.downloadFailed": "Download failed",
            "update.unzipFailed": "Extract failed",
            "update.noApp": "App not found",
            "update.installFailed": "Install failed",
            "update.installing": "Installing...",
            "empty.title": "No Claude Code data found",
            "empty.message": "Select your home folder to start tracking.\nThe app will automatically find .claude data.",
            "folder.select": "Select",
            "folder.message": "Select your home folder. Token Jandi will automatically find Claude Code data.",
            "settings.privacy": "Privacy Policy",
            "settings.displayMode": "Menu bar display",
            "settings.displayTokens": "Tokens",
            "settings.displayPercentage": "Session usage",
            "usage.noCredentials": "No credentials found",
            "usage.authFailed": "Auth failed",
            "usage.fiveHour": "Session (5h)",
            "usage.sevenDay": "Weekly (7d)",
            "usage.resetsIn": "Resets in",
            "usage.fetching": "Fetching...",
            "usage.synced": "Synced",
            "usage.cliNotFound": "Claude CLI not found",
            "usage.loginFailed": "Login failed",
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
            "settings.update": "업데이트",
            "settings.checkUpdate": "업데이트 확인",
            "settings.updateAvailable": "업데이트 가능",
            "update.checking": "확인 중...",
            "update.upToDate": "최신 버전",
            "update.checkFailed": "확인 실패",
            "update.noAsset": "다운로드 파일 없음",
            "update.downloadFailed": "다운로드 실패",
            "update.unzipFailed": "압축 해제 실패",
            "update.noApp": "앱을 찾을 수 없음",
            "update.installFailed": "설치 실패",
            "update.installing": "설치 중...",
            "empty.title": "Claude Code 사용 정보 없음",
            "empty.message": "홈 폴더를 선택하면 자동으로\nClaude Code 데이터를 찾습니다.",
            "folder.select": "선택",
            "folder.message": "홈 폴더를 선택해주세요. Token Jandi가 자동으로 Claude Code 데이터를 찾습니다.",
            "settings.privacy": "개인정보 처리방침",
            "settings.displayMode": "메뉴바 표시",
            "settings.displayTokens": "토큰 수",
            "settings.displayPercentage": "세션 사용량",
            "usage.noCredentials": "인증 정보 없음",
            "usage.authFailed": "인증 실패",
            "usage.fiveHour": "세션 (5시간)",
            "usage.sevenDay": "주간 (7일)",
            "usage.resetsIn": "리셋까지",
            "usage.fetching": "조회 중...",
            "usage.synced": "동기화됨",
            "usage.cliNotFound": "Claude CLI를 찾을 수 없음",
            "usage.loginFailed": "로그인 실패",
        ],
    ]
}
