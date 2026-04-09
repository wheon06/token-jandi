import SwiftUI
import Combine

enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case min1 = 60
    case min5 = 300
    case min10 = 600
    case min15 = 900
    case min30 = 1800

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return L("refresh.off")
        case .min1: return "1 min"
        case .min5: return "5 min"
        case .min10: return "10 min"
        case .min15: return "15 min"
        case .min30: return "30 min"
        }
    }
}

class HeatmapViewModel: ObservableObject {
    @Published var cells: [DayCell] = []
    @Published var selectedCell: DayCell?
    @Published var hasClaudeData = false
    @Published var selectedSource: UsageSourceFilter = .all {
        didSet {
            buildCells(from: dailyUsage)
        }
    }

    @AppStorage("refreshInterval") var refreshIntervalRaw: Int = RefreshInterval.min5.rawValue {
        didSet { setupTimer() }
    }

    private let calendar = Calendar.current
    private let weeksToShow = 20
    private var timer: AnyCancellable?
    private var dailyUsage: [Date: DailyUsageData] = [:]
    var folderAccessManager: FolderAccessManager?

    init() {
        loadData()
        setupTimer()
    }

    private func setupTimer() {
        timer?.cancel()
        guard refreshIntervalRaw > 0 else { return }
        timer = Timer.publish(every: TimeInterval(refreshIntervalRaw), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadData()
            }
    }

    func loadData() {
        // Use the selected root URL if available (sandbox), otherwise default to the user's home folder.
        let parser = ClaudeLogParser(claudeDir: folderAccessManager?.claudeDirectoryURL)

        dailyUsage = parser.parseDailyUsage()
        hasClaudeData = parser.hasAnyDataSource && dailyUsage.values.contains { $0.filtered(by: .all) != nil }
        buildCells(from: dailyUsage)
    }

    var todayUsage: TokenUsage? {
        usage(for: Date(), filter: selectedSource)
    }

    var allSourcesTodayUsage: TokenUsage? {
        usage(for: Date(), filter: .all)
    }

    var currentStreak: Int {
        let today = calendar.startOfDay(for: Date())
        let sorted = cells.filter { $0.date <= today }.sorted { $0.date > $1.date }
        var streak = 0
        for cell in sorted {
            if cell.level > 0 {
                streak += 1
            } else {
                break
            }
        }
        return streak
    }

    var weeklyTokens: Int {
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return cells
            .filter { $0.date >= oneWeekAgo }
            .compactMap { $0.usage?.totalTokens }
            .reduce(0, +)
    }

    var totalTokens: Int {
        cells.compactMap { $0.usage?.totalTokens }.reduce(0, +)
    }

    /// Recent 14 days with usage for daily chart
    var recentDailyData: [(date: Date, tokens: Int)] {
        let cutoff = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: Date()))!
        return cells
            .filter { $0.date >= cutoff }
            .map { (date: $0.date, tokens: $0.usage?.totalTokens ?? 0) }
            .sorted { $0.date < $1.date }
    }

    /// Monthly aggregated data
    var monthlyData: [(label: String, tokens: Int)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        var grouped: [Int: (String, Int)] = [:]

        for cell in cells {
            let year = calendar.component(.year, from: cell.date)
            let month = calendar.component(.month, from: cell.date)
            let key = year * 100 + month
            let tokens = cell.usage?.totalTokens ?? 0
            if let existing = grouped[key] {
                grouped[key] = (existing.0, existing.1 + tokens)
            } else {
                grouped[key] = (formatter.string(from: cell.date), tokens)
            }
        }

        return grouped.sorted { $0.key < $1.key }
            .map { (label: $0.value.0, tokens: $0.value.1) }
    }

    /// Group cells into columns (weeks), each column has up to 7 rows (days)
    var weeks: [[DayCell]] {
        var result: [[DayCell]] = []
        var currentWeek: [DayCell] = []

        for (index, cell) in cells.enumerated() {
            let weekday = calendar.component(.weekday, from: cell.date)
            currentWeek.append(cell)

            if weekday == 7 || index == cells.count - 1 {
                result.append(currentWeek)
                currentWeek = []
            }
        }
        return result
    }

    var monthLabels: [(String, Int)] {
        var labels: [(String, Int)] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var lastMonth = -1
        for (weekIndex, week) in weeks.enumerated() {
            guard let firstDay = week.first else { continue }
            let month = calendar.component(.month, from: firstDay.date)
            if month != lastMonth {
                labels.append((formatter.string(from: firstDay.date), weekIndex))
                lastMonth = month
            }
        }
        return labels
    }

    private func buildCells(from dailyUsage: [Date: DailyUsageData]) {
        let today = calendar.startOfDay(for: Date())
        let totalDays = weeksToShow * 7
        let selectedDate = selectedCell?.date

        guard let rawStart = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else { return }
        let rawWeekday = calendar.component(.weekday, from: rawStart)
        guard let start = calendar.date(byAdding: .day, value: -(rawWeekday - 1), to: rawStart) else { return }

        let actualDays = calendar.dateComponents([.day], from: start, to: today).day! + 1

        let rebuiltCells = (0..<actualDays).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let day = calendar.startOfDay(for: date)
            let usage = dailyUsage[day]?.filtered(by: selectedSource)

            return DayCell(date: day, usage: usage)
        }

        cells = rebuiltCells

        if let selectedDate {
            selectedCell = rebuiltCells.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) })
        }
    }

    private func usage(for date: Date, filter: UsageSourceFilter) -> TokenUsage? {
        let day = calendar.startOfDay(for: date)
        return dailyUsage[day]?.filtered(by: filter)
    }
}
