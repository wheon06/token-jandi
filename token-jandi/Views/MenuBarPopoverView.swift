import SwiftUI

/// Tabs follow the question being asked: how much was used, how much is left,
/// and how the app behaves.
enum PopoverTab: String {
    case usage
    case limits
    case settings
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var folderAccess: FolderAccessManager
    @ObservedObject var localization = LocalizationManager.shared
    @StateObject private var bridge: ClaudeBridgeController
    @State private var currentTab: PopoverTab

    private static let lastTabKey = "lastPopoverTab"

    init(viewModel: UsageViewModel, folderAccess: FolderAccessManager) {
        self.viewModel = viewModel
        self.folderAccess = folderAccess
        _bridge = StateObject(wrappedValue: ClaudeBridgeController(folderAccess: folderAccess))
        // Reopen on the tab that was being looked at, so limits stay one click away
        // for people who mostly check those.
        let saved = UserDefaults.standard.string(forKey: Self.lastTabKey).flatMap(PopoverTab.init(rawValue:))
        _currentTab = State(initialValue: saved ?? .usage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            HStack(spacing: 4) {
                TabButton(icon: "leaf.fill", title: L("tab.usage"), isSelected: currentTab == .usage) { select(.usage) }
                TabButton(icon: "gauge.with.needle", title: L("tab.limits"), isSelected: currentTab == .limits) { select(.limits) }
                TabButton(icon: "gearshape.fill", title: L("tab.settings"), isSelected: currentTab == .settings) { select(.settings) }

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
                case .usage:
                    UsageContentView(viewModel: viewModel)
                case .limits:
                    LimitsContentView(viewModel: viewModel, bridge: bridge)
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

    private func select(_ tab: PopoverTab) {
        currentTab = tab
        // Settings is a detour, not a place to come back to.
        if tab != .settings {
            UserDefaults.standard.set(tab.rawValue, forKey: Self.lastTabKey)
        }
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
    let title: String
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
        .help(title)
        .accessibilityLabel(title)
    }
}

// MARK: - Usage tab

/// The same history drawn three ways.
enum UsageChart: String, CaseIterable {
    case heatmap
    case daily
    case monthly

    var title: String {
        switch self {
        case .heatmap: return L("chart.heatmap")
        case .daily: return L("chart.daily")
        case .monthly: return L("chart.monthly")
        }
    }
}

struct UsageContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("usageChart") private var chartRaw = UsageChart.heatmap.rawValue

    private var chart: UsageChart {
        UsageChart(rawValue: chartRaw) ?? .heatmap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.groupSpacing) {
            UsageHeroView(viewModel: viewModel)

            VStack(alignment: .leading, spacing: 12) {
                TextChoices(
                    options: UsageChart.allCases.map { ($0, $0.title) },
                    selection: Binding(get: { chart }, set: { chartRaw = $0.rawValue })
                )

                switch chart {
                case .heatmap:
                    GrassHeatmapView(viewModel: viewModel)
                case .daily:
                    BarChartView(data: viewModel.recentDailyData.map {
                        (label: dayLabel($0.date), value: $0.tokens, detail: usageDateString($0.date))
                    })
                case .monthly:
                    BarChartView(data: viewModel.monthlyData.map {
                        (label: $0.label, value: $0.tokens, detail: $0.label)
                    })
                }
            }
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

/// "11. 20. (Fri)" in the selected language; shared by the heatmap and the chart.
func usageDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = LocalizationManager.shared.locale
    formatter.setLocalizedDateFormatFromTemplate("M d EEE")
    return formatter.string(from: date)
}

/// One big number, then three supporting numbers. No sentences: anything that
/// needs explaining lives in a tooltip.
struct UsageHeroView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(L("stats.today"))
                        .font(Theme.body)
                        .foregroundColor(.secondary)
                    Spacer()
                    SourceFilter(selection: $viewModel.selectedSource)
                }

                Text(formatTokenCount(viewModel.summaryStats.todayTokens))
                    .font(Theme.hero)
                    .monospacedDigit()
            }

            HStack(alignment: .top, spacing: 0) {
                StatColumn(
                    label: L("stats.last7Days"),
                    value: formatTokenCount(viewModel.summaryStats.last7DaysTokens)
                )
                StatColumn(
                    label: L("stats.streak"),
                    value: "\(viewModel.currentStreak)\(L("stats.daysSuffix"))"
                )
                StatColumn(
                    label: L("stats.total"),
                    value: formatTokenCount(viewModel.summaryStats.totalTokens) + (estimateNotice == nil ? "" : "+")
                )
                .help(estimateNotice ?? "")
            }
        }
    }

    /// Set while the totals include Codex threads that only survive in the thread
    /// database. Those are a lower bound, so the total reads "1.2B+" and the full
    /// explanation is the tooltip.
    private var estimateNotice: String? {
        guard viewModel.selectedSource != .claude,
              let fallback = viewModel.codexDatabaseFallback,
              fallback.threadCount > 0 else { return nil }
        return L("stats.codexEstimate", fallback.threadCount, formatTokenCount(fallback.tokens))
    }
}

/// Small gray label over a value; three of these share the row equally.
struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(Theme.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(Theme.stat)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain text choices; the selected one is simply darker and heavier.
struct TextChoices<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    init(options: [(Value, String)], selection: Binding<Value>) {
        self.options = options.map { (value: $0.0, title: $0.1) }
        _selection = selection
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(options, id: \.value) { option in
                Button(action: { selection = option.value }) {
                    Text(option.title)
                        .font(.system(size: 11, weight: selection == option.value ? .semibold : .regular))
                        .foregroundColor(selection == option.value ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SourceFilter: View {
    @Binding var selection: UsageSourceFilter

    var body: some View {
        TextChoices(options: UsageSourceFilter.allCases.map { ($0, $0.title) }, selection: $selection)
    }
}

// MARK: - Limits tab

/// One group per agent: its plan in the header, then what is left of each window.
struct LimitsContentView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var bridge: ClaudeBridgeController

    var body: some View {
        let claude = viewModel.claudeRateLimitStatus
        let codex = viewModel.codexRateLimitStatus
        let claudePlan = viewModel.claudePlan?.displayName
        let codexPlan = codex?.planName
        let showsClaude = claude?.hasLimits == true || claudePlan != nil || bridge.isAvailable
        let showsCodex = codex?.hasLimits == true || codexPlan != nil

        VStack(alignment: .leading, spacing: Theme.rowSpacing) {
            if showsClaude {
                AgentLimitsGroup(name: L("source.claude"), plan: claudePlan) {
                    if let claude, claude.hasLimits {
                        if let window = claude.fiveHour {
                            LimitRow(name: limitWindowTitle(minutes: window.windowMinutes), window: window)
                        }
                        if let window = claude.sevenDay {
                            LimitRow(name: limitWindowTitle(minutes: window.windowMinutes), window: window)
                        }
                        if let spend = claude.spendLimit {
                            SpendLimitRow(spendLimit: spend)
                        }
                    } else if bridge.isInstalled {
                        Text(L("settings.claudeBridge.waiting"))
                            .font(Theme.caption)
                            .foregroundColor(.secondary)
                    } else if bridge.isAvailable {
                        HStack {
                            Text(L("limits.connect"))
                                .font(Theme.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(L("claudeLimit.hintAction")) { bridge.setEnabled(true) }
                                .font(Theme.caption)
                                .controlSize(.small)
                        }
                        .help(L("claudeLimit.hintHelp"))
                    }
                }
            }

            if showsCodex {
                AgentLimitsGroup(name: L("source.codex"), plan: codexPlan) {
                    if let window = codex?.primary {
                        LimitRow(name: limitWindowTitle(minutes: window.windowMinutes), window: window)
                    }
                    if let window = codex?.secondary {
                        LimitRow(name: limitWindowTitle(minutes: window.windowMinutes), window: window)
                    }
                }
            }

            if !showsClaude && !showsCodex {
                Text(L("limits.empty"))
                    .font(Theme.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .onAppear { bridge.refresh() }
    }
}

struct AgentLimitsGroup<Content: View>: View {
    let name: String
    let plan: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        SectionGroup {
            HStack(alignment: .firstTextBaseline) {
                Text(name)
                    .font(Theme.title)
                Spacer()
                if let plan {
                    Text(plan)
                        .font(Theme.caption)
                        .foregroundColor(.secondary)
                }
            }
            content()
        }
    }
}

/// `5h   ▮▮▮▯▯▯  23%   10/24 02:00`
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
                .frame(width: 64, alignment: .leading)

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

// MARK: - Bar chart

struct BarChartView: View {
    let data: [(label: String, value: Int, detail: String)]
    @State private var hoveredIndex: Int? = nil

    private var maxValue: Int {
        data.map(\.value).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            .frame(height: 124, alignment: .bottom)

            // Same place and wording as the line under the heatmap: the hovered
            // bar, or the latest one.
            if let index = hoveredIndex ?? data.indices.last, index < data.count {
                Text("\(data[index].detail) · \(formatTokenCount(data[index].value))")
                    .font(Theme.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
    }

    private func barColor(index: Int, value: Int) -> Color {
        if value == 0 { return Theme.track }
        if let hoveredIndex, hoveredIndex != index { return Theme.accent.opacity(0.35) }
        return Theme.accent
    }

    private func barHeight(_ value: Int) -> CGFloat {
        guard maxValue > 0 else { return 3 }
        return max(3, CGFloat(value) / CGFloat(maxValue) * 104)
    }
}

// MARK: - Loading and empty states

struct LoadingStateView: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity, minHeight: 180)
    }
}

struct EmptyStateView: View {
    @ObservedObject var folderAccess: FolderAccessManager

    var body: some View {
        VStack(spacing: 14) {
            Text(L("empty.title"))
                .font(Theme.stat)

            Button(L("empty.action")) { folderAccess.requestFolderAccess() }
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}
