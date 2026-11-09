import Foundation
import Observation

nonisolated struct AppSettings: Codable, Equatable, Sendable {
    var hasCompletedOnboarding = false
    var useDemoData = false
    var sleepNeedHours = 7.5
    var maxHeartRateOverride: Int?

    private static let key = "settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    var scoringConfiguration: ScoringConfiguration {
        ScoringConfiguration(sleepNeedBaseline: sleepNeedHours * 3600, maxHeartRateOverride: maxHeartRateOverride.map(Double.init))
    }
}

@Observable
final class AppModel {
    /// Days of history to read: 30 visible days plus a 30-day baseline behind the oldest one.
    static let historyDays = 60
    static let visibleDays = 30

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            if settings.scoringConfiguration != oldValue.scoringConfiguration { rescore() }
        }
    }

    private(set) var days: [DayMetrics] = []
    private(set) var maxHeartRate = 190.0
    private(set) var maxHeartRateSource = MaxHeartRateSource.standard
    private(set) var isLoading = false
    private(set) var lastUpdated: Date?
    var errorMessage: String?
    var selectedDate = Calendar.current.startOfDay(for: .now)

    private var snapshot: HealthSnapshot?

    init(settings: AppSettings = .load()) {
        self.settings = settings
    }

    // MARK: - Days

    var visibleDays: ArraySlice<DayMetrics> { days.suffix(Self.visibleDays) }

    var selectedDay: DayMetrics? {
        days.last { $0.date == selectedDate } ?? days.last
    }

    var isViewingToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var canGoBack: Bool {
        guard let first = visibleDays.first else { return false }
        return selectedDate > first.date
    }

    var canGoForward: Bool {
        guard let last = days.last else { return false }
        return selectedDate < last.date
    }

    func step(by days: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        if let index = self.days.firstIndex(where: { $0.date == date }), index >= self.days.count - Self.visibleDays {
            selectedDate = date
        }
    }

    /// The `count` days ending with `day`, oldest first.
    func history(endingAt day: DayMetrics, count: Int) -> [DayMetrics] {
        guard let index = days.firstIndex(where: { $0.date == day.date }) else { return [] }
        return Array(days[max(0, index - count + 1)...index])
    }

    // MARK: - Loading

    private var source: HealthDataSource {
        settings.useDemoData ? DemoDataSource() : HealthKitService.shared
    }

    func connectAppleHealth() async {
        do {
            try await HealthKitService.shared.requestAuthorization()
            settings.useDemoData = false
            settings.hasCompletedOnboarding = true
            snapshot = nil
            days = []
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startDemo() async {
        settings.useDemoData = true
        settings.hasCompletedOnboarding = true
        snapshot = nil
        days = []
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let now = Date.now
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -Self.historyDays, to: calendar.startOfDay(for: now))!
        do {
            snapshot = try await source.fetchSnapshot(in: DateInterval(start: start, end: now))
            rescore()
            lastUpdated = now
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rescore() {
        guard let snapshot else { return }
        let result = ScoringEngine(configuration: settings.scoringConfiguration).score(snapshot)
        days = result.days
        maxHeartRate = result.maxHeartRate
        maxHeartRateSource = result.maxHeartRateSource
        if !days.contains(where: { $0.date == selectedDate }) {
            selectedDate = days.last?.date ?? Calendar.current.startOfDay(for: .now)
        }
    }
}
