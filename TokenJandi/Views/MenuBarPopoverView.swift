import SwiftUI

enum PopoverTab {
    case heatmap
    case detail
    case settings
}

struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: HeatmapViewModel
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
                    Button(action: { viewModel.loadData() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(L("action.refresh"))
                }
            }

            Divider()

            if !viewModel.hasClaudeData && currentTab != .settings {
                EmptyStateView()
            } else {
                switch currentTab {
                case .heatmap:
                    HeatmapContentView(viewModel: viewModel)
                case .detail:
                    DetailContentView(viewModel: viewModel)
                case .settings:
                    SettingsView(localization: localization)
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
                SimpleDetailView(cell: selected)
            }
        }
    }
}

/// Minimal detail shown on heatmap hover — just date + total
struct SimpleDetailView: View {
    let cell: DayCell

    var body: some View {
        HStack(spacing: 8) {
            Text(dateString)
                .foregroundColor(.secondary)
            if let usage = cell.usage {
                Text(usage.totalTokensFormatted)
                    .fontWeight(.semibold)
            } else {
                Text(L("heatmap.noUsage"))
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd (E)"
        return formatter.string(from: cell.date)
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
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Shared

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
