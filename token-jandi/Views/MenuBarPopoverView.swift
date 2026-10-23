import SwiftUI

enum PopoverTab {
    case heatmap
    case detail
    case settings
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var folderAccess: FolderAccessManager
    @ObservedObject var localization = LocalizationManager.shared
    @StateObject private var bridge: ClaudeBridgeController
    @State private var currentTab: PopoverTab = .heatmap

    init(viewModel: UsageViewModel, folderAccess: FolderAccessManager) {
        self.viewModel = viewModel
        self.folderAccess = folderAccess
        _bridge = StateObject(wrappedValue: ClaudeBridgeController(folderAccess: folderAccess))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            HStack(spacing: 4) {
                TabButton(icon: "leaf.fill", isSelected: currentTab == .heatmap) { currentTab = .heatmap }
                TabButton(icon: "chart.bar.fill", isSelected: currentTab == .detail) { currentTab = .detail }
                TabButton(icon: "gearshape.fill", isSelected: currentTab == .settings) { currentTab = .settings }

                Spacer()

                if currentTab != .settings {
                    RefreshButton(viewModel: viewModel)
                }
            }

            if viewModel.isLoadingWithoutData && currentTab != .settings {
                LoadingStateView()
            } else if !viewModel.hasUsageData && currentTab != .settings {
                EmptyStateView(folderAccess: folderAccess)
            } else {
                switch currentTab {
                case .heatmap:
                    HeatmapContentView(viewModel: viewModel, bridge: bridge)
                case .detail:
                    DetailContentView(viewModel: viewModel)
                case .settings:
                    SettingsView(
                        localization: localization,
                        viewModel: viewModel,
                        folderAccess: folderAccess,
                        bridge: bridge
                    )
                }
            }
        }
        .padding(Theme.padding)
        .frame(width: 380)
        .id(localization.selectedLanguage)
    }
}

struct RefreshButton: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        Button(action: { viewModel.loadData(force: true) }) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(Theme.body)
                    .opacity(viewModel.isRefreshing ? 0 : 1)
                if viewModel.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                }
            }
            .frame(width: 24, height: 24)
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshing)
        .help(viewModel.isRefreshing ? L("action.refreshing") : L("action.refresh"))
    }
}

struct TabButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isSelected ? .primary : Color.secondary.opacity(0.6))
                .frame(width: 28, height: 24)
                .background(isSelected ? Theme.groupBackground : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Heatmap tab

struct HeatmapContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var bridge: ClaudeBridgeController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            UsageHeroView(viewModel: viewModel)

            LimitsSection(viewModel: viewModel, bridge: bridge)

            GrassHeatmapView(viewModel: viewModel)
        }
    }
}

/// One big number, then everything else in a quiet line under it.
struct UsageHeroView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(L("stats.today"))
                    .font(Theme.caption)
                    .foregroundColor(.secondary)
                Spacer()
                SourceFilter(selection: $viewModel.selectedSource)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatTokenCount(viewModel.summaryStats.todayTokens))
                    .font(Theme.hero)
                    .monospacedDigit()
                Text(L("stats.tokens"))
                    .font(Theme.body)
                    .foregroundColor(.secondary)
            }

            Text(summaryLine)
                .font(Theme.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var summaryLine: String {
        [
            "\(L("stats.last7Days")) \(formatTokenCount(viewModel.summaryStats.last7DaysTokens))",
            "\(L("stats.streak")) \(viewModel.currentStreak)\(L("stats.daysSuffix"))",
            "\(L("stats.total")) \(formatTokenCount(viewModel.summaryStats.totalTokens))",
        ].joined(separator: "  ·  ")
    }
}

/// Plain text choices; the selected one is simply darker and heavier.
struct SourceFilter: View {
    @Binding var selection: UsageSourceFilter

    var body: some View {
        HStack(spacing: 10) {
            ForEach(UsageSourceFilter.allCases) { source in
                Button(action: { selection = source }) {
                    Text(source.title)
                        .font(.system(size: 11, weight: selection == source ? .semibold : .regular))
                        .foregroundColor(selection == source ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Limits

struct LimitsSection: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var bridge: ClaudeBridgeController

    private var showsClaude: Bool { viewModel.selectedSource != .codex }
    private var showsCodex: Bool { viewModel.selectedSource != .claude }

    var body: some View {
        let claude = showsClaude ? viewModel.claudeRateLimitStatus : nil
        let codex = showsCodex ? viewModel.codexRateLimitStatus : nil
        let offerBridge = showsClaude && claude == nil && bridge.isAvailable && !bridge.isInstalled

        if claude?.hasLimits == true || codex?.hasLimits == true || offerBridge {
            SectionGroup(L("limits.title")) {
                if let claude {
                    if let window = claude.fiveHour {
                        LimitRow(name: limitRowName(L("source.claude"), window), window: window)
                    }
                    if let window = claude.sevenDay {
                        LimitRow(name: limitRowName(L("source.claude"), window), window: window)
                    }
                    if let spend = claude.spendLimit {
                        SpendLimitRow(spendLimit: spend)
                    }
                } else if offerBridge {
                    HStack {
                        Text(L("claudeLimit.hint"))
                            .font(Theme.body)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(L("claudeLimit.hintAction")) { bridge.setEnabled(true) }
                            .font(Theme.caption)
                            .controlSize(.small)
                            .help(L("claudeLimit.hintHelp"))
                    }
                }

                if let codex {
                    if let window = codex.primary {
                        LimitRow(name: limitRowName(L("source.codex"), window), window: window)
                    }
                    if let window = codex.secondary {
                        LimitRow(name: limitRowName(L("source.codex"), window), window: window)
                    }
                }
            }
        }
    }

    private func limitRowName(_ provider: String, _ window: RateLimitWindow) -> String {
        "\(provider) \(limitWindowTitle(minutes: window.windowMinutes))"
    }
}

/// `Claude 5h   ▮▮▮▯▯▯  23%   10/24 02:00`
struct LimitRow: View {
    let name: String
    let window: RateLimitWindow

    var body: some View {
        // Re-evaluate once a minute so an elapsed window reads as reset.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let percent = window.effectiveUsedPercent(at: context.date)
            LimitRowLayout(
                name: name,
                fraction: percent / 100,
                percentText: percentString(percent),
                caption: window.hasReset(at: context.date)
                    ? L("limit.resetDone")
                    : limitDateString(window.resetsAt)
            )
        }
    }
}

struct SpendLimitRow: View {
    let spendLimit: SpendLimitStatus

    var body: some View {
        LimitRowLayout(
            name: L("spendLimit.title", periodTitle),
            fraction: spendLimit.usedPercent / 100,
            percentText: percentString(spendLimit.usedPercent),
            caption: caption
        )
    }

    private var periodTitle: String {
        switch spendLimit.period {
        case "daily": return L("limit.period.daily")
        case "weekly": return L("limit.period.weekly")
        case "monthly": return L("limit.period.monthly")
        default: return L("limit.period.unknown")
        }
    }

    private var caption: String {
        if let used = spendLimit.usedUSD, let limit = spendLimit.limitUSD {
            return String(format: "$%.0f / $%.0f", used, limit)
        }
        return limitDateString(spendLimit.resetsAt)
    }
}

struct LimitRowLayout: View {
    let name: String
    let fraction: Double
    let percentText: String
    let caption: String

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(Theme.body)
                .lineLimit(1)
                .frame(width: 92, alignment: .leading)

            UsageBar(fraction: fraction)

            Text(percentText)
                .font(Theme.number)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)

            Text(caption)
                .font(Theme.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 78, alignment: .trailing)
        }
    }
}

func percentString(_ percent: Double) -> String {
    "\(Int(percent.rounded()))%"
}

/// "5h", "7d", … derived from the window length.
func limitWindowTitle(minutes: Int) -> String {
    if minutes > 0, minutes % 1440 == 0 {
        return L("limit.windowDays", minutes / 1440)
    }
    if minutes > 0, minutes % 60 == 0 {
        return L("limit.windowHours", minutes / 60)
    }
    return L("limit.windowMinutes", minutes)
}

func limitDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = LocalizationManager.shared.locale
    formatter.setLocalizedDateFormatFromTemplate("M d HH:mm")
    return formatter.string(from: date)
}

// MARK: - Chart tab

enum ChartPeriod: String, CaseIterable {
    case daily, monthly
}

struct DetailContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var period: ChartPeriod = .daily

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            HStack {
                Picker("", selection: $period) {
                    Text(L("chart.daily")).tag(ChartPeriod.daily)
                    Text(L("chart.monthly")).tag(ChartPeriod.monthly)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)

                Spacer()

                SourceFilter(selection: $viewModel.selectedSource)
            }

            switch period {
            case .daily:
                BarChartView(data: viewModel.recentDailyData.map { (label: dayLabel($0.date), value: $0.tokens) })
            case .monthly:
                BarChartView(data: viewModel.monthlyData.map { (label: $0.label, value: $0.tokens) })
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
        VStack(alignment: .leading, spacing: 10) {
            // The hovered bar's value, or the scale, in the same spot.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let index = hoveredIndex, index < data.count {
                    Text(formatTokenCount(data[index].value))
                        .font(Theme.hero)
                        .monospacedDigit()
                    Text(data[index].label)
                        .font(Theme.body)
                        .foregroundColor(.secondary)
                } else {
                    Text(formatTokenCount(maxValue))
                        .font(Theme.hero)
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                    Text(L("chart.max"))
                        .font(Theme.body)
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(index: index, value: item.value))
                            .frame(height: barHeight(item.value))

                        Text(item.label)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredIndex = hovering ? index : nil
                    }
                }
            }
            .frame(height: 120)
        }
    }

    private func barColor(index: Int, value: Int) -> Color {
        if value == 0 { return Theme.track }
        if let hoveredIndex, hoveredIndex != index { return Theme.accent.opacity(0.35) }
        return Theme.accent
    }

    private func barHeight(_ value: Int) -> CGFloat {
        guard maxValue > 0 else { return 3 }
        return max(3, CGFloat(value) / CGFloat(maxValue) * 100)
    }
}

// MARK: - Loading and empty states

struct LoadingStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(L("loading.title"))
                .font(Theme.body)
            Text(L("loading.message"))
                .font(Theme.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct EmptyStateView: View {
    @ObservedObject var folderAccess: FolderAccessManager

    var body: some View {
        VStack(spacing: 10) {
            Text(L("empty.title"))
                .font(Theme.title)
            Text(L("empty.message"))
                .font(Theme.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(L("folder.select")) { folderAccess.requestFolderAccess() }
                .controlSize(.regular)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
