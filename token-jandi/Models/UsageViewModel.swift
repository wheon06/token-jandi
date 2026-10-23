import SwiftUI
import Combine

nonisolated enum RefreshInterval: Int, CaseIterable, Identifiable {
    case off = 0
    case min1 = 60
    case min5 = 300
    case min10 = 600
    case min15 = 900
    case min30 = 1800

    var id: Int { rawValue }
}

extension RefreshInterval {
    var label: String {
        switch self {
        case .off: return L("refresh.off")
        default: return L("refresh.minutes", rawValue / 60)
        }
    }
}

class UsageViewModel: ObservableObject {
    @Published private(set) var cells: [DayCell] = []
    @Published var selectedCell: DayCell?
    @Published private(set) var hasUsageData = false
    @Published private(set) var codexRateLimitStatus: CodexRateLimitStatus?
    @Published private(set) var claudeRateLimitStatus: ClaudeRateLimitStatus?
    @Published private(set) var summaryStats = UsageSummaryStats()
    @Published private(set) var isRefreshing = false
    @Published var selectedSource: UsageSourceFilter = .all {
        didSet { rebuildDerivedData() }
    }

    @AppStorage("refreshInterval") var refreshIntervalRaw: Int = RefreshInterval.min5.rawValue {
        didSet { setupTimer() }
    }

    let folderAccess: FolderAccessManager

    private let store = UsageLogStore()
    private let weeksToShow = 20
    private var refreshTimer: AnyCancellable?
    private var subscriptions = Set<AnyCancellable>()
    private var dailyUsage: [Date: DailyUsageData] = [:]
    private var refreshRequestID = 0

    private var calendar: Calendar { .current }

    init(folderAccess: FolderAccessManager) {
        self.folderAccess = folderAccess

        folderAccess.$dataRootURL
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.loadData(force: true)
            }
            .store(in: &subscriptions)

        // Roll "today" over at midnight even when auto refresh is off.
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &subscriptions)

        loadData()
        setupTimer()
    }

    var isLoadingWithoutData: Bool {
        isRefreshing && !hasUsageData
    }

    private func setupTimer() {
        refreshTimer?.cancel()
        guard refreshIntervalRaw > 0 else { return }
        refreshTimer = Timer.publish(every: TimeInterval(refreshIntervalRaw), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.loadData()
            }
    }

    /// Re-reads the logs. Without `force` this is cheap when nothing changed: only
    /// file metadata is compared. With `force` the data is rebuilt even if unchanged.
    func loadData(force: Bool = false) {
        if isRefreshing && !force {
            return
        }

        refreshRequestID += 1
        let requestID = refreshRequestID
        let dataRootURL = folderAccess.dataRootURL
        isRefreshing = true

        Task { [weak self, store] in
            let snapshot = await store.load(dataRootURL: dataRootURL, force: force)

            guard let self, self.refreshRequestID == requestID else { return }
            if let snapshot {
                self.apply(snapshot)
            }
            self.isRefreshing = false
        }
    }

    private func apply(_ snapshot: UsageLogStore.Snapshot) {
        dailyUsage = snapshot.report.dailyUsage
        codexRateLimitStatus = snapshot.report.codexRateLimitStatus
        claudeRateLimitStatus = snapshot.report.claudeRateLimitStatus
        hasUsageData = snapshot.hasAnyDataSource
            && dailyUsage.values.contains { $0.totals.hasUsage }
        rebuildDerivedData()
    }

    // MARK: - Derived values

    var allSourcesTodayUsage: TokenUsage? {
        usage(for: Date(), filter: .all)
    }

    /// Consecutive days with usage ending today, or ending yesterday when today has
    /// no usage yet.
    var currentStreak: Int {
        let today = calendar.startOfDay(for: Date())
        let descending = cells.filter { $0.date <= today }.sorted { $0.date > $1.date }

        var streak = 0
        for (index, cell) in descending.enumerated() {
            if cell.level > 0 {
                streak += 1
            } else if index == 0 {
                continue // today may simply not have started yet
            } else {
                break
            }
        }
        return streak
    }

    func todayTokens(for filter: UsageSourceFilter) -> Int {
        usage(for: Date(), filter: filter)?.totalTokens ?? 0
    }

    func last7DaysTokens(for filter: UsageSourceFilter) -> Int {
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today

        return dailyUsage
            .filter { date, _ in date >= weekStart && date <= today }
            .compactMap { _, usage in usage.filtered(by: filter)?.totalTokens }
            .reduce(0, +)
    }

    /// Recent 14 days for the daily chart
    var recentDailyData: [(date: Date, tokens: Int)] {
        let today = calendar.startOfDay(for: Date())
        return (0..<14).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (date: date, tokens: dailyUsage[date]?.filtered(by: selectedSource)?.totalTokens ?? 0)
        }
    }

    /// Up to the last six calendar months, each summed over every logged day of
    /// that month, so the first bar isn't truncated by the heatmap window.
    var monthlyData: [(label: String, tokens: Int)] {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")

        let components = calendar.dateComponents([.year, .month], from: Date())
        guard let currentMonth = calendar.date(from: components) else { return [] }

        let months: [(label: String, tokens: Int)] = (0..<6).reversed().compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: currentMonth),
                  let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return nil }

            let tokens = dailyUsage
                .filter { date, _ in date >= monthStart && date < monthEnd }
                .compactMap { _, usage in usage.filtered(by: selectedSource)?.totalTokens }
                .reduce(0, +)
            return (label: formatter.string(from: monthStart), tokens: tokens)
        }

        let firstNonEmpty = months.firstIndex { $0.tokens > 0 } ?? months.count - 1
        return Array(months[max(firstNonEmpty, 0)...])
    }

    /// Group cells into columns (weeks), each column has up to 7 rows (days)
    private(set) var weeks: [[DayCell]] = []

    /// Month name and the week column where it starts.
    private(set) var monthLabels: [(name: String, weekIndex: Int)] = []

    private func rebuildDerivedData() {
        rebuildCells()
        weeks = buildWeeks(from: cells)
        monthLabels = buildMonthLabels(from: weeks)
        summaryStats = buildSummaryStats()

        if let selectedDate = selectedCell?.date {
            selectedCell = cells.first { calendar.isDate($0.date, inSameDayAs: selectedDate) }
        }
    }

    private func rebuildCells() {
        let today = calendar.startOfDay(for: Date())
        let totalDays = weeksToShow * 7

        guard let rawStart = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else { return }
        let rawWeekday = calendar.component(.weekday, from: rawStart)
        guard let start = calendar.date(byAdding: .day, value: -(rawWeekday - 1), to: rawStart),
              let dayCount = calendar.dateComponents([.day], from: start, to: today).day.map({ $0 + 1 }),
              dayCount > 0 else { return }

        cells = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = calendar.startOfDay(for: date)
            return DayCell(date: day, usage: dailyUsage[day]?.filtered(by: selectedSource))
        }
    }

    private func buildWeeks(from cells: [DayCell]) -> [[DayCell]] {
        var result: [[DayCell]] = []
        var currentWeek: [DayCell] = []

        for (index, cell) in cells.enumerated() {
            currentWeek.append(cell)
            if calendar.component(.weekday, from: cell.date) == 7 || index == cells.count - 1 {
                result.append(currentWeek)
                currentWeek = []
            }
        }
        return result
    }

    private func buildMonthLabels(from weeks: [[DayCell]]) -> [(name: String, weekIndex: Int)] {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")

        var labels: [(name: String, weekIndex: Int)] = []
        var lastMonth = -1
        for (weekIndex, week) in weeks.enumerated() {
            guard let firstDay = week.first else { continue }
            let month = calendar.component(.month, from: firstDay.date)
            if month != lastMonth {
                labels.append((name: formatter.string(from: firstDay.date), weekIndex: weekIndex))
                lastMonth = month
            }
        }
        return labels
    }

    private func buildSummaryStats() -> UsageSummaryStats {
        // "Total" reflects all logged days for the selected source, not just the
        // visible heatmap window, so usage older than the shown weeks isn't dropped.
        let totalTokens = dailyUsage.values
            .compactMap { $0.filtered(by: selectedSource)?.totalTokens }
            .reduce(0, +)

        return UsageSummaryStats(
            todayTokens: todayTokens(for: selectedSource),
            last7DaysTokens: last7DaysTokens(for: selectedSource),
            totalTokens: totalTokens
        )
    }

    private func usage(for date: Date, filter: UsageSourceFilter) -> TokenUsage? {
        dailyUsage[calendar.startOfDay(for: date)]?.filtered(by: filter)
    }
}

struct UsageSummaryStats: Equatable {
    var todayTokens: Int = 0
    var last7DaysTokens: Int = 0
    var totalTokens: Int = 0
}
