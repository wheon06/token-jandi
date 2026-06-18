import SwiftUI

enum PopoverTab {
    case heatmap
    case detail
    case settings
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: HeatmapViewModel
    @ObservedObject var folderAccess: FolderAccessManager
    @ObservedObject var localization = LocalizationManager.shared
    @State private var currentTab: PopoverTab = .heatmap

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 2) {
                    TabButton(icon: "leaf.fill", isSelected: currentTab == .heatmap) {
                        currentTab = .heatmap
                    }
                    TabButton(icon: "chart.bar", isSelected: currentTab == .detail) {
                        currentTab = .detail
                    }
                    TabButton(icon: "gearshape", isSelected: currentTab == .settings) {
                        currentTab = .settings
                    }
                }

                Spacer()

                if currentTab == .heatmap {
                    Button(action: { viewModel.loadData(force: true) }) {
                        ZStack {
                            Image(systemName: "arrow.clockwise")
                                .opacity(viewModel.isRefreshing ? 0 : 1)

                            if viewModel.isRefreshing {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.55)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isRefreshing)
                    .help(viewModel.isRefreshing ? L("action.refreshing") : L("action.refresh"))
                }
            }

            Divider()

            if viewModel.isLoadingWithoutData && currentTab != .settings {
                LoadingStateView()
            } else if !viewModel.hasClaudeData && currentTab != .settings {
                EmptyStateView(folderAccess: folderAccess)
            } else {
                switch currentTab {
                case .heatmap:
                    HeatmapContentView(viewModel: viewModel)
                case .detail:
                    DetailContentView(viewModel: viewModel)
                case .settings:
                    SettingsView(localization: localization, viewModel: viewModel)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .id(localization.selectedLanguage)
    }
}

struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.green.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Heatmap Tab (simple)

struct HeatmapContentView: View {
    @ObservedObject var viewModel: HeatmapViewModel

    var body: some View {
        VStack(spacing: 12) {
            SourceFilterChips(selection: $viewModel.selectedSource)

            HStack(spacing: 10) {
                StatCard(
                    title: L("stats.today"),
                    value: formatTokenCount(viewModel.summaryStats.todayTokens),
                    unit: L("stats.tokens")
                )
                StatCard(
                    title: L("stats.thisWeek"),
                    value: formatTokenCount(viewModel.summaryStats.weeklyTokens),
                    unit: L("stats.tokens")
                )
                StatCard(
                    title: L("stats.streak"),
                    value: "\(viewModel.currentStreak)",
                    unit: L("stats.days")
                )
                StatCard(
                    title: L("stats.total"),
                    value: formatTokenCount(viewModel.summaryStats.totalTokens),
                    unit: L("stats.tokens")
                )
            }

            if let status = viewModel.codexRateLimitStatus, status.hasLimits {
                CodexRateLimitsView(status: status)
            }

            Divider()

            GrassHeatmapView(viewModel: viewModel)

            // Simple inline detail on hover
            if let selected = viewModel.selectedCell {
                SimpleDetailView(cell: selected, selectedSource: viewModel.selectedSource)
            }
        }
    }
}

struct CodexRateLimitsView: View {
    let status: CodexRateLimitStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(L("codexLimit.title"), systemImage: "speedometer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                if let planType = status.planType, !planType.isEmpty {
                    Text(planType.capitalized)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 6)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }

            HStack(spacing: 8) {
                if let primary = status.primary {
                    CodexLimitWindowCard(title: L("codexLimit.primary"), window: primary)
                }

                if let secondary = status.secondary {
                    CodexLimitWindowCard(title: L("codexLimit.secondary"), window: secondary)
                }
            }
        }
    }
}

struct CodexLimitWindowCard: View {
    let title: String
    let window: CodexRateLimitWindow

    private var fraction: CGFloat {
        CGFloat(min(max(window.usedPercent / 100, 0), 1))
    }

    private var tint: Color {
        if window.usedPercent >= 90 {
            return .red
        }
        if window.usedPercent >= 70 {
            return .orange
        }
        return .green
    }

    private var percentText: String {
        if window.usedPercent.rounded() == window.usedPercent {
            return "\(Int(window.usedPercent))%"
        }
        return String(format: "%.1f%%", window.usedPercent)
    }

    private var resetText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("M d HH:mm")
        return "\(L("codexLimit.resets")) \(formatter.string(from: window.resetsAt))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(percentText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(tint)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(nsColor: .separatorColor).opacity(0.25))

                    Capsule()
                        .fill(tint)
                        .frame(width: max(4, proxy.size.width * fraction))
                }
            }
            .frame(height: 6)

            Text(resetText)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

/// Minimal detail shown on heatmap hover — just date + total
struct SimpleDetailView: View {
    let cell: DayCell
    let selectedSource: UsageSourceFilter

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(dateString, systemImage: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                if let usage = cell.usage {
                    Text(usage.totalTokensFormatted)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                } else {
                    Text(L("heatmap.noUsage"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            if let usage = cell.usage, !visibleSources(for: usage).isEmpty {
                HStack(spacing: 6) {
                    ForEach(visibleSources(for: usage), id: \.self) { source in
                        SourceTokenBadge(
                            title: source.title,
                            value: formatTokenCount(usage.totalTokens(for: source)),
                            tint: sourceTint(for: source)
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("M d EEE")
        return formatter.string(from: cell.date)
    }

    private func visibleSources(for usage: TokenUsage) -> [UsageProvider] {
        switch selectedSource {
        case .all:
            return usage.activeSources
        case .claude:
            return usage.totalTokens(for: .claude) > 0 ? [.claude] : []
        case .codex:
            return usage.totalTokens(for: .codex) > 0 ? [.codex] : []
        }
    }

    private func sourceTint(for source: UsageProvider) -> Color {
        switch source {
        case .claude:
            return .mint
        case .codex:
            return .green
        }
    }
}

// MARK: - Chart Tab

enum ChartPeriod: String, CaseIterable {
    case daily, monthly
}

struct DetailContentView: View {
    @ObservedObject var viewModel: HeatmapViewModel
    @State private var period: ChartPeriod = .daily

    var body: some View {
        VStack(spacing: 10) {
            SourceFilterChips(selection: $viewModel.selectedSource)

            // Period toggle
            Picker("", selection: $period) {
                Text(L("chart.daily")).tag(ChartPeriod.daily)
                Text(L("chart.monthly")).tag(ChartPeriod.monthly)
            }
            .pickerStyle(.segmented)

            // Chart
            switch period {
            case .daily:
                BarChartView(
                    data: viewModel.recentDailyData.map { (label: dayLabel($0.date), value: $0.tokens) }
                )
            case .monthly:
                BarChartView(
                    data: viewModel.monthlyData.map { (label: $0.label, value: $0.tokens) }
                )
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

struct BarChartView: View {
    let data: [(label: String, value: Int)]
    @State private var hoveredIndex: Int? = nil

    private var maxValue: Int {
        data.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(spacing: 4) {
            // Hover value display
            HStack {
                Spacer()
                if let idx = hoveredIndex, idx < data.count {
                    Text(formatTokenCount(data[idx].value))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.green)
                } else {
                    Text(formatTokenCount(maxValue))
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .frame(height: 14)

            // Bars
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(index: index, value: item.value))
                            .frame(height: barHeight(item.value))

                        Text(item.label)
                            .font(.system(size: 7))
                            .foregroundColor(hoveredIndex == index ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .onHover { hovering in
                        hoveredIndex = hovering ? index : nil
                    }
                }
            }
            .frame(height: 100)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func barColor(index: Int, value: Int) -> Color {
        if value == 0 { return Color.green.opacity(0.1) }
        return hoveredIndex == index ? Color.green.opacity(0.85) : Color.green
    }

    private func barHeight(_ value: Int) -> CGFloat {
        guard maxValue > 0 else { return 2 }
        let ratio = CGFloat(value) / CGFloat(maxValue)
        return max(2, ratio * 80)
    }
}

// MARK: - Loading and Empty States

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            VStack(spacing: 4) {
                Text(L("loading.title"))
                    .font(.caption)
                    .fontWeight(.medium)

                Text(L("loading.message"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct EmptyStateView: View {
    @ObservedObject var folderAccess: FolderAccessManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(L("empty.title"))
                .font(.caption)
                .fontWeight(.medium)
            Text(L("empty.message"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { folderAccess.requestFolderAccess() }) {
                HStack(spacing: 4) {
                    Image(systemName: "folder.badge.plus")
                    Text(L("folder.select"))
                }
                .font(.caption)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}

// MARK: - Shared

struct SourceFilterChips: View {
    @Binding var selection: UsageSourceFilter

    var body: some View {
        HStack(spacing: 6) {
            ForEach(UsageSourceFilter.allCases) { source in
                Button(action: { selection = source }) {
                    Text(source.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selection == source ? .green : .primary)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule()
                                .fill(selection == source
                                      ? Color.green.opacity(0.15)
                                      : Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}

struct SourceTokenBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)

            Text(title)
                .foregroundColor(.secondary)

            Text(value)
                .fontWeight(.semibold)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.vertical, 4)
        .padding(.horizontal, 9)
        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.9)))
        .overlay(
            Capsule()
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
