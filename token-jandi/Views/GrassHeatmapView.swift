import SwiftUI

struct GrassHeatmapView: View {
    @ObservedObject var viewModel: UsageViewModel

    private let cellSize: CGFloat = 13
    private let cellSpacing: CGFloat = 3
    private let labelWidth: CGFloat = 24

    private var dayLabels: [(key: String, display: String)] {
        [
            ("Sun", ""), ("Mon", L("day.mon")), ("Tue", ""),
            ("Wed", L("day.wed")), ("Thu", ""), ("Fri", L("day.fri")), ("Sat", "")
        ]
    }

    var body: some View {
        let weeks = viewModel.weeks
        let monthLabels = viewModel.monthLabels

        VStack(alignment: .leading, spacing: 6) {
            // Month labels
            HStack(spacing: 0) {
                ForEach(Array(monthLabels.enumerated()), id: \.offset) { index, label in
                    let nextWeekIndex = index + 1 < monthLabels.count
                        ? monthLabels[index + 1].weekIndex
                        : weeks.count
                    let span = nextWeekIndex - label.weekIndex

                    // A month that only spans one column has no room for its name.
                    Text(span >= 2 ? label.name : "")
                        .font(Theme.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(width: CGFloat(span) * (cellSize + cellSpacing), alignment: .leading)
                        .clipped()
                }
            }
            .padding(.leading, labelWidth)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: cellSpacing) {
                    ForEach(dayLabels, id: \.key) { item in
                        Text(item.display)
                            .font(Theme.caption)
                            .foregroundColor(.secondary)
                            .frame(height: cellSize)
                    }
                }
                .frame(width: labelWidth, alignment: .leading)

                HStack(alignment: .top, spacing: cellSpacing) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: cellSpacing) {
                            ForEach(week) { cell in
                                GrassCellView(cell: cell, size: cellSize, isSelected: viewModel.selectedCell?.id == cell.id)
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

            // One line: hovered day on the left, legend on the right.
            HStack(alignment: .firstTextBaseline) {
                // Today until a day is hovered, so the line never has to explain itself.
                if let cell = viewModel.selectedCell ?? viewModel.cells.last {
                    Text(detailLine(for: cell))
                        .font(Theme.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 3) {
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(colorForLevel(level))
                            .frame(width: 9, height: 9)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    /// "Oct 22 (Wed) · 33.8M · Claude 30.1M · Codex 3.7M"
    private func detailLine(for cell: DayCell) -> String {
        var parts = [usageDateString(cell.date)]

        guard let usage = cell.usage else {
            parts.append(L("heatmap.noUsage"))
            return parts.joined(separator: " · ")
        }

        parts.append(usage.totalTokensFormatted)
        let sources = usage.activeSources.filter { source in
            switch viewModel.selectedSource {
            case .all: return true
            case .claude: return source == .claude
            case .codex: return source == .codex
            }
        }
        if sources.count > 1 || viewModel.selectedSource == .all {
            for source in sources {
                parts.append("\(source.title) \(formatTokenCount(usage.totalTokens(for: source)))")
            }
        }
        return parts.joined(separator: " · ")
    }
}

struct GrassCellView: View {
    let cell: DayCell
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(colorForLevel(cell.level))
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.35 : 0), lineWidth: 1)
            )
    }
}

func colorForLevel(_ level: Int) -> Color {
    switch level {
    case 0: return Theme.track
    case 1: return Theme.accent.opacity(0.3)
    case 2: return Theme.accent.opacity(0.5)
    case 3: return Theme.accent.opacity(0.75)
    case 4: return Theme.accent
    default: return Color.clear
    }
}
