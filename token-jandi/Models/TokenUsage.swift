import Foundation
import SwiftUI

enum UsageProvider: String, CaseIterable, Hashable {
    case claude
    case codex

    var title: String {
        switch self {
        case .claude: return L("source.claude")
        case .codex: return L("source.codex")
        }
    }
}

enum UsageSourceFilter: String, CaseIterable, Identifiable {
    case all
    case claude
    case codex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L("source.all")
        case .claude: return L("source.claude")
        case .codex: return L("source.codex")
        }
    }

    var provider: UsageProvider? {
        switch self {
        case .all: return nil
        case .claude: return .claude
        case .codex: return .codex
        }
    }
}

struct UsageTotals {
    var messageCount: Int = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var tokensByModel: [String: Int] = [:]
    var apiCallCount: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }

    var hasUsage: Bool {
        totalTokens > 0 || messageCount > 0 || apiCallCount > 0
    }

    mutating func merge(_ other: UsageTotals) {
        messageCount += other.messageCount
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheReadTokens += other.cacheReadTokens
        cacheCreationTokens += other.cacheCreationTokens
        apiCallCount += other.apiCallCount

        for (model, tokens) in other.tokensByModel {
            tokensByModel[model, default: 0] += tokens
        }
    }
}

struct TokenUsage: Identifiable {
    let id = UUID()
    let date: Date
    let totals: UsageTotals
    let sourceBreakdown: [UsageProvider: UsageTotals]

    var messageCount: Int { totals.messageCount }
    var inputTokens: Int { totals.inputTokens }
    var outputTokens: Int { totals.outputTokens }
    var cacheReadTokens: Int { totals.cacheReadTokens }
    var cacheCreationTokens: Int { totals.cacheCreationTokens }
    var tokensByModel: [String: Int] { totals.tokensByModel }
    var apiCallCount: Int { totals.apiCallCount }

    var totalTokens: Int {
        totals.totalTokens
    }

    /// 0 = no usage, 1~4 = intensity levels based on total tokens
    var level: Int {
        switch totalTokens {
        case 0: return 0
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

    /// Model summary
    var modelSummary: String {
        tokensByModel.map { model, tokens in
            "\(shortModelName(model)): \(formatTokenCount(tokens))"
        }.joined(separator: ", ")
    }

    var activeSources: [UsageProvider] {
        UsageProvider.allCases.filter { sourceBreakdown[$0]?.hasUsage == true }
    }

    func totalTokens(for provider: UsageProvider) -> Int {
        sourceBreakdown[provider]?.totalTokens ?? 0
    }
}

struct DayCell: Identifiable {
    var id: Date { date }
    let date: Date
    let usage: TokenUsage?

    var level: Int { usage?.level ?? 0 }
}

func formatTokenCount(_ count: Int) -> String {
    if count >= 1_000_000 {
        return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
        return String(format: "%.1fK", Double(count) / 1_000)
    }
    return "\(count)"
}

func formatPercent(_ ratio: Double) -> String {
    let pct = ratio * 100
    if pct < 1 && pct > 0 { return "<1%" }
    return "\(Int(pct))%"
}

func usageLevelColor(for ratio: Double) -> Color {
    switch ratio {
    case ..<0.5: return .green
    case ..<0.8: return .yellow
    case ..<0.95: return .orange
    default: return .red
    }
}

private func shortModelName(_ name: String) -> String {
    if name.contains("opus") { return "Opus" }
    if name.contains("sonnet") { return "Sonnet" }
    if name.contains("haiku") { return "Haiku" }
    return name
}
