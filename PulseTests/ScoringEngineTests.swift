import Foundation
import Testing
@testable import Pulse

struct ScoringEngineTests {
    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

    private var engine: ScoringEngine {
        ScoringEngine(configuration: ScoringConfiguration(), calendar: Self.calendar)
    }

    private struct Night {
        var hrv: Double = 55
        var restingHR: Double = 52
        var sleepHours: Double = 7.5
    }

    /// One day per night: sleep 11 PM → wake, with heart rate and HRV readings during it.
    private func snapshot(_ nights: [Night]) -> HealthSnapshot {
        let end = Self.calendar.date(byAdding: .day, value: nights.count, to: Self.start)!.addingTimeInterval(-1)
        var snapshot = HealthSnapshot(interval: DateInterval(start: Self.start, end: end))
        snapshot.profile = UserProfile(age: 30, sex: .male)
        for (index, night) in nights.enumerated() {
            let day = Self.calendar.date(byAdding: .day, value: index, to: Self.start)!
            let bed = day.addingTimeInterval(-3600)
            let wake = bed.addingTimeInterval(night.sleepHours * 3600)
            snapshot.sleep.append(SleepSample(start: bed, end: wake, stage: .core, source: "watch"))
            var time = bed
            while time < wake {
                snapshot.heartRate.append(Reading(date: time, value: night.restingHR))
                time.addTimeInterval(300)
            }
            for i in 1...3 {
                snapshot.hrv.append(Reading(date: bed.addingTimeInterval(Double(i) * 3600), value: night.hrv))
            }
        }
        return snapshot
    }

    private func baselineNights(_ count: Int) -> [Night] {
        (0..<count).map { Night(hrv: 55 + Double($0 % 3 - 1) * 4, restingHR: 52 + Double($0 % 3 - 1), sleepHours: 7.5) }
    }

    // MARK: - Strain

    @Test func strainScaleIsBoundedAndMonotonic() {
        #expect(ScoringEngine.strain(forLoad: 0) == 0)
        let values = [10.0, 50, 100, 200, 400, 1000].map(ScoringEngine.strain(forLoad:))
        #expect(values == values.sorted())
        #expect(values.last! < StrainSummary.maximum)
    }

    @Test func everydayHeartRateBuildsNoStrain() {
        let readings = (0..<100).map { Reading(date: Self.start.addingTimeInterval(Double($0) * 300), value: 80) }
        let load = engine.cardioLoad(readings[...], until: Self.start.addingTimeInterval(30_000), restingHR: 55, maxHR: 190, sex: .male)
        #expect(load.load == 0)
        #expect(load.zoneMinutes.allSatisfy { $0 == 0 })
    }

    @Test func fortyFiveMinuteRunIsModerateToHighStrain() {
        let readings = (0..<(45 * 6)).map { Reading(date: Self.start.addingTimeInterval(Double($0) * 10), value: 155) }
        let load = engine.cardioLoad(readings[...], until: Self.start.addingTimeInterval(45 * 60), restingHR: 55, maxHR: 190, sex: .male)
        let strain = ScoringEngine.strain(forLoad: load.load)
        #expect((10...16).contains(strain))
        #expect(abs(load.zoneMinutes[3] - 45) < 0.5) // 155 / 190 = 82% → zone 4
    }

    // MARK: - Recovery

    @Test func recoveryNeedsABaselineFirst() {
        let days = engine.score(snapshot(baselineNights(4))).days
        #expect(days.last?.recovery == nil)
        #expect(days.last?.baselineNights == 3)
    }

    @Test func highHRVAndLowRestingHRIsGreen() {
        let nights = baselineNights(14) + [Night(hrv: 72, restingHR: 48, sleepHours: 8)]
        let recovery = engine.score(snapshot(nights)).days.last?.recovery
        #expect(recovery?.zone == .green)
    }

    @Test func lowHRVAndHighRestingHRIsRed() {
        let nights = baselineNights(14) + [Night(hrv: 36, restingHR: 60, sleepHours: 5)]
        let recovery = engine.score(snapshot(nights)).days.last?.recovery
        #expect(recovery?.zone == .red)
    }

    @Test func averageNightIsYellow() {
        let nights = baselineNights(14) + [Night(sleepHours: 6.5)]
        let recovery = engine.score(snapshot(nights)).days.last?.recovery
        #expect(recovery?.zone == .yellow)
    }

    // MARK: - Sleep

    @Test func sleepDebtDoesNotCompound() {
        let nights = (0..<10).map { _ in Night(sleepHours: 5) }
        let days = engine.score(snapshot(nights)).days
        let needs = days.compactMap { $0.sleep?.need.total }
        #expect(needs.allSatisfy { $0 <= 7.5 * 3600 + 45 * 60 + 1 })
    }

    @Test func prefersWatchStagesOverDuplicateSources() {
        let day = Self.start
        let bed = day.addingTimeInterval(-3600)
        let samples = [
            // iPhone bedtime schedule: one long unstaged block.
            SleepSample(start: bed, end: bed.addingTimeInterval(8 * 3600), stage: .unspecified, source: "phone"),
            // Watch: staged, slightly shorter.
            SleepSample(start: bed.addingTimeInterval(600), end: bed.addingTimeInterval(3 * 3600), stage: .core, source: "watch"),
            SleepSample(start: bed.addingTimeInterval(3 * 3600), end: bed.addingTimeInterval(4 * 3600), stage: .deep, source: "watch"),
            SleepSample(start: bed.addingTimeInterval(4 * 3600), end: bed.addingTimeInterval(7 * 3600), stage: .rem, source: "watch"),
        ]
        let sessions = SleepSessions(day: day, samples: samples)
        #expect(sessions.main?.allSatisfy { $0.source == "watch" } == true)
        #expect(SleepSessions.asleepTime(sessions.main ?? []) == 7 * 3600 - 600)
    }

    @Test func afternoonSleepIsANap() {
        let day = Self.start
        let bed = day.addingTimeInterval(-3600)
        let samples = [
            SleepSample(start: bed, end: bed.addingTimeInterval(7 * 3600), stage: .core, source: "watch"),
            SleepSample(start: day.addingTimeInterval(14 * 3600), end: day.addingTimeInterval(14.5 * 3600), stage: .core, source: "watch"),
        ]
        let sessions = SleepSessions(day: day, samples: samples)
        #expect(sessions.main?.first?.start == bed)
        #expect(sessions.naps.count == 1)
    }

    // MARK: - Demo pipeline

    @Test func demoDataProducesSensibleScores() {
        let now = Date.now
        let start = Calendar.current.date(byAdding: .day, value: -AppModel.historyDays, to: Calendar.current.startOfDay(for: now))!
        let snapshot = DemoDataGenerator(now: now).snapshot(for: DateInterval(start: start, end: now))
        let days = ScoringEngine().score(snapshot).days.suffix(AppModel.visibleDays)

        #expect(days.count == AppModel.visibleDays)
        // Today may not have last night yet if this runs just after midnight.
        #expect(days.dropLast().allSatisfy { $0.recovery != nil && $0.sleep != nil })
        #expect(days.allSatisfy { (0...StrainSummary.maximum).contains($0.strain.score) })
        let zones = Set(days.compactMap { $0.recovery?.zone })
        #expect(zones.count >= 2, "Demo should show a mix of recovery zones")
    }
}
