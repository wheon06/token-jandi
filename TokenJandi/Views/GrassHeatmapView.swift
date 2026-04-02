import SwiftUI

struct GrassHeatmapView: View {
    @ObservedObject var viewModel: HeatmapViewModel

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    private var dayLabels: [(key: String, display: String)] {
        [
            ("Sun", ""), ("Mon", L("day.mon")), ("Tue", ""),
            ("Wed", L("day.wed")), ("Thu", ""), ("Fri", L("day.fri")), ("Sat", "")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Month labels
            HStack(spacing: 0) {
                ForEach(Array(viewModel.monthLabels.enumerated()), id: \.offset) { index, label in
                    let (name, weekIndex) = label
                    let nextWeekIndex = index + 1 < viewModel.monthLabels.count
                        ? viewModel.monthLabels[index + 1].1
                        : viewModel.weeks.count

                    Text(name)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(width: CGFloat(nextWeekIndex - weekIndex) * (cellSize + cellSpacing), alignment: .leading)
                }
            }
            .padding(.leading, 28)

            // Grid
            HStack(alignment: .top, spacing: 0) {
                // Day labels
                VStack(alignment: .trailing, spacing: cellSpacing) {
                    ForEach(dayLabels, id: \.key) { item in
                        Text(item.display)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .frame(width: 28)

                // Cells
                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(viewModel.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week) { cell in
                                GrassCellView(cell: cell, size: cellSize)
                                    .onTapGesture {
                                        viewModel.selectedCell = cell
                                    }
                                    .onHover { hovering in
                                        if hovering {
                                            viewModel.selectedCell = cell
                                        }
                                    }
                            }
                        }
                    }
                }
            }

            // Legend — right aligned, compact
            HStack(spacing: 3) {
                Spacer()
                Text(L("heatmap.less"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForLevel(level))
                        .frame(width: 10, height: 10)
                }
                Text(L("heatmap.more"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct GrassCellView: View {
    let cell: DayCell
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(colorForLevel(cell.level))
            .frame(width: size, height: size)
            .help(tooltipText)
    }

    /// Simple tooltip — just date + total tokens
    private var tooltipText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd"
        let dateStr = formatter.string(from: cell.date)

        if let usage = cell.usage {
            return "\(dateStr) — \(usage.totalTokensFormatted)"
        }
        return dateStr
    }
}

func colorForLevel(_ level: Int) -> Color {
    switch level {
    case 0: return Color(nsColor: NSColor.systemGray).opacity(0.2)
    case 1: return Color.green.opacity(0.3)
    case 2: return Color.green.opacity(0.5)
    case 3: return Color.green.opacity(0.75)
    case 4: return Color.green
    default: return Color.clear
    }
}

func formatNumber(_ n: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

/// Localization helper — uses LocalizationManager singleton
func L(_ key: String) -> String {
    LocalizationManager.shared.localized(key)
}
