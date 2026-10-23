import SwiftUI

struct GrassHeatmapView: View {
    @ObservedObject var viewModel: UsageViewModel

    private let cellSize: CGFloat = 12
    private let cellSpacing: CGFloat = 3

    private var dayLabels: [(key: String, display: String)] {
        [
            ("Sun", ""), ("Mon", L("day.mon")), ("Tue", ""),
            ("Wed", L("day.wed")), ("Thu", ""), ("Fri", L("day.fri")), ("Sat", "")
        ]
    }

    var body: some View {
        let weeks = viewModel.weeks
        let monthLabels = viewModel.monthLabels

        VStack(alignment: .leading, spacing: 4) {
            // Month labels
            HStack(spacing: 0) {
                ForEach(Array(monthLabels.enumerated()), id: \.offset) { index, label in
                    let nextWeekIndex = index + 1 < monthLabels.count
                        ? monthLabels[index + 1].weekIndex
                        : weeks.count
                    let span = nextWeekIndex - label.weekIndex

                    // A month that only spans one column has no room for its name;
                    // leave the column blank so neighbouring labels don't overlap.
                    Text(span >= 2 ? label.name : "")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: CGFloat(span) * (cellSize + cellSpacing), alignment: .leading)
                        .clipped()
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
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week) { cell in
                                Button {
                                    viewModel.selectedCell = cell
                                } label: {
                                    GrassCellView(cell: cell, size: cellSize)
                                }
                                .buttonStyle(.plain)
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
