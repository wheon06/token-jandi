import Foundation

struct TokenUsage: Identifiable {
    let id = UUID()
    let date: Date
    let messageCount: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let tokensByModel: [String: Int]
    let apiCallCount: Int

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
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
}

struct DayCell: Identifiable {
    let id = UUID()
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

private func shortModelName(_ name: String) -> String {
    if name.contains("opus") { return "Opus" }
    if name.contains("sonnet") { return "Sonnet" }
    if name.contains("haiku") { return "Haiku" }
    return name
}
