import SwiftUI

enum PopoverTab {
    case heatmap
    case detail
    case settings
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: HeatmapViewModel
    @ObservedObject var folderAccess: FolderAccessManager
    @ObservedObject var usageService: AnthropicUsageService
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
                    Button(action: {
                        viewModel.loadData()
                        if usageService.hasCredentials {
                            usageService.fetchUsage(force: true)
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("action.refresh"))
                }
            }

            Divider()

            if !viewModel.hasClaudeData && currentTab != .settings {
                EmptyStateView(folderAccess: folderAccess)
            } else {
                switch currentTab {
                case .heatmap:
                    HeatmapContentView(viewModel: viewModel)
                    if usageService.hasCredentials {
                        Divider()
                        ApiUsageBannerView(usageService: usageService)
                    }
                case .detail:
                    DetailContentView(viewModel: viewModel)
                case .settings:
                    SettingsView(localization: localization, viewModel: viewModel, usageService: usageService)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .id(localization.selectedLanguage)
    }
}

// MARK: - API Usage Banner

struct ApiUsageBannerView: View {
    @ObservedObject var usageService: AnthropicUsageService

    var body: some View {
        let ratio = usageService.usageRatio
        let color = usageLevelColor(for: ratio)
        let weeklyRatio = usageService.weeklyUsageRatio
        let weeklyColor = usageLevelColor(for: weeklyRatio)

        VStack(spacing: 8) {
            UsageBarRow(
                label: L("usage.fiveHour"),
                ratio: ratio,
                color: color,
                trailingText: usageService.resetTimeFormatted.map { "\(L("usage.resetsIn")) \($0)" }
            )

            UsageBarRow(
                label: L("usage.sevenDay"),
                ratio: weeklyRatio,
                color: weeklyColor,
                trailingText: nil
            )

            HStack {
                if let data = usageService.usageData, data.isExtraUsageEnabled {
                    Text("Max")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.purple)
                        .cornerRadius(3)
                }
                Spacer()
                switch usageService.fetchState {
                case .loading:
                    HStack(spacing: 2) {
                        ProgressView().scaleEffect(0.4).frame(width: 10, height: 10)
                        Text(L("usage.fetching")).font(.caption2).foregroundColor(.secondary)
                    }
                case .error(let msg):
                    Text(msg).font(.caption2).foregroundColor(.red).lineLimit(1)
                case .loaded:
                    Text(L("usage.synced")).font(.caption2).foregroundColor(.secondary)
                case .idle:
                    EmptyView()
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct UsageBarRow: View {
    let label: String
    let ratio: Double
    let color: Color
    let trailingText: String?

    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatPercent(ratio))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(
                            width: geometry.size.width * min(ratio, 1.0),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            if let trailingText {
                HStack {
                    Spacer()
                    Text(trailingText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
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
                    value: viewModel.todayUsage?.totalTokensFormatted ?? "0",
                    unit: L("stats.tokens")
                )
                StatCard(
                    title: L("stats.thisWeek"),
                    value: formatTokenCount(viewModel.weeklyTokens),
                    unit: L("stats.tokens")
                )
                StatCard(
                    title: L("stats.streak"),
                    value: "\(viewModel.currentStreak)",
                    unit: L("stats.days")
                )
                StatCard(
                    title: L("stats.total"),
                    value: formatTokenCount(viewModel.totalTokens),
                    unit: L("stats.tokens")
                )
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

// MARK: - Empty State

struct EmptyStateView: View {
    @ObservedObject var folderAccess: FolderAccessManager

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.trianglebadge.exclamationmark")
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
