import Foundation

nonisolated enum UsageProvider: String, CaseIterable, Hashable, Codable {
    case claude
    case codex
}

nonisolated enum UsageSourceFilter: String, CaseIterable, Identifiable {
    case all
    case claude
    case codex

    var id: String { rawValue }
}

nonisolated enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case claudeToday
    case codexToday
    case iconOnly

    var id: String { rawValue }
}

/// Token counts for one day and one source (or the sum of all sources).
nonisolated struct UsageTotals: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    var hasUsage: Bool {
        totalTokens > 0
    }

    mutating func add(_ other: UsageTotals) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreationTokens += other.cacheCreationTokens
    }
}

/// Aggregated daily usage from all sources.
nonisolated struct DailyUsageData: Equatable {
    let date: Date
    var totals = UsageTotals()
    var sourceBreakdown: [UsageProvider: UsageTotals] = [:]

    var totalTokens: Int {
        totals.totalTokens
    }

    mutating func add(_ usage: UsageTotals, source: UsageProvider) {
        totals.add(usage)
        sourceBreakdown[source, default: UsageTotals()].add(usage)
    }

    mutating func merge(_ other: DailyUsageData) {
        totals.add(other.totals)
        for (source, usage) in other.sourceBreakdown {
            sourceBreakdown[source, default: UsageTotals()].add(usage)
        }
    }

    func filtered(by filter: UsageSourceFilter) -> TokenUsage? {
        let selectedTotals: UsageTotals
        switch filter {
        case .all:
            selectedTotals = totals
        case .claude:
            guard let claudeTotals = sourceBreakdown[.claude] else { return nil }
            selectedTotals = claudeTotals
        case .codex:
            guard let codexTotals = sourceBreakdown[.codex] else { return nil }
            selectedTotals = codexTotals
        }

        guard selectedTotals.hasUsage else { return nil }

        return TokenUsage(
            date: date,
            totals: selectedTotals,
            sourceBreakdown: sourceBreakdown
        )
    }
}

nonisolated func mergeDailyUsage(
    _ incoming: [Date: DailyUsageData],
    into result: inout [Date: DailyUsageData]
) {
    for (date, data) in incoming {
        result[date, default: DailyUsageData(date: date)].merge(data)
    }
}

/// Usage for a single day after applying the selected source filter.
nonisolated struct TokenUsage: Equatable {
    let date: Date
    let totals: UsageTotals
    let sourceBreakdown: [UsageProvider: UsageTotals]

    var inputTokens: Int { totals.inputTokens }
    var outputTokens: Int { totals.outputTokens }
    var cacheReadTokens: Int { totals.cacheReadTokens }
    var cacheCreationTokens: Int { totals.cacheCreationTokens }

    var totalTokens: Int {
        totals.totalTokens
    }

    /// 0 = no usage, 1~4 = intensity levels based on total tokens
    var level: Int {
        switch totalTokens {
        case ...0: return 0
        case 1...1_000_000: return 1          // ~1M
        case 1_000_001...10_000_000: return 2  // ~10M
        case 10_000_001...30_000_000: return 3 // ~30M
        default: return 4                       // 30M+
        }
    }

    /// Human-readable token count (e.g. "4.5M", "142.6K")
    var totalTokensFormatted: String {
        formatTokenCount(totalTokens)
    }

    var activeSources: [UsageProvider] {
        UsageProvider.allCases.filter { sourceBreakdown[$0]?.hasUsage == true }
    }

    func totalTokens(for provider: UsageProvider) -> Int {
        sourceBreakdown[provider]?.totalTokens ?? 0
    }
}

nonisolated struct DayCell: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let usage: TokenUsage?

    var level: Int { usage?.level ?? 0 }
}

nonisolated func formatTokenCount(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.1fK", Double(count) / 1_000)
    }
    return "\(count)"
}

// MARK: - Presentation

extension UsageProvider {
    var title: String {
        switch self {
        case .claude: return L("source.claude")
        case .codex: return L("source.codex")
        }
    }
}

extension UsageSourceFilter {
    var title: String {
        switch self {
        case .all: return L("source.all")
        case .claude: return L("source.claude")
        case .codex: return L("source.codex")
        }
    }
}

extension MenuBarDisplayMode {
    var title: String {
        switch self {
        case .today: return L("menuBar.today")
        case .thisWeek: return L("menuBar.last7Days")
        case .claudeToday: return L("menuBar.claudeToday")
        case .codexToday: return L("menuBar.codexToday")
        case .iconOnly: return L("menuBar.iconOnly")
        }
    }
}
