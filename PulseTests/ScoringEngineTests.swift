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
        /// How much heart rate climbs per hour through the night.
        var heartRateRisePerHour: Double = 0
        var wristTemperature: Double?
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
                let hours = time.timeIntervalSince(bed) / 3600
                snapshot.heartRate.append(Reading(date: time, value: night.restingHR + night.heartRateRisePerHour * hours))
                time.addTimeInterval(300)
            }
            if let temperature = night.wristTemperature {
                snapshot.wristTemperature.append(Reading(date: wake, value: temperature))
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

    @Test func strainScaleIsLogarithmicAndBounded() {
        #expect(ScoringEngine.strain(forLoad: 0) == 0)
        let values = [10.0, 50, 100, 200, 400, 1000].map(ScoringEngine.strain(forLoad:))
        #expect(values == values.sorted())
        #expect(values.last! < StrainSummary.maximum)
        // A full day in zone 5 is the ceiling.
        #expect(abs(ScoringEngine.strain(forLoad: 5 * 1440) - StrainSummary.maximum) < 1e-9)
        // Doubling the load adds a roughly constant amount of strain.
        let step1 = ScoringEngine.strain(forLoad: 400) - ScoringEngine.strain(forLoad: 200)
        let step2 = ScoringEngine.strain(forLoad: 800) - ScoringEngine.strain(forLoad: 400)
        #expect(abs(step1 - step2) < 0.05)
    }

    @Test func loadIsZoneWeightedMinutes() {
        // 20 min in zone 2 (65% of 190) then 10 min in zone 5 (95%).
        let readings = (0..<180).map { i in
            Reading(date: Self.start.addingTimeInterval(Double(i) * 10), value: i < 120 ? 123.5 : 180.5)
        }
        let load = engine.cardioLoad(readings[...], until: Self.start.addingTimeInterval(30 * 60), maxHR: 190)
        #expect(abs(load.load - (20 * 2 + 10 * 5)) < 0.5)
    }

    @Test func everydayHeartRateBuildsNoStrain() {
        let readings = (0..<100).map { Reading(date: Self.start.addingTimeInterval(Double($0) * 300), value: 80) }
        let load = engine.cardioLoad(readings[...], until: Self.start.addingTimeInterval(30_000), maxHR: 190)
        #expect(load.load == 0)
        #expect(load.zoneMinutes.allSatisfy { $0 == 0 })
    }

    @Test func fortyFiveMinuteRunIsModerateToHighStrain() {
        let readings = (0..<(45 * 6)).map { Reading(date: Self.start.addingTimeInterval(Double($0) * 10), value: 155) }
        let load = engine.cardioLoad(readings[...], until: Self.start.addingTimeInterval(45 * 60), maxHR: 190)
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

    @Test func feverishWristTemperatureLowersRecovery() {
        let baseline = baselineNights(14).enumerated().map { index, night in
            var night = night
            night.wristTemperature = 35 + Double(index % 3 - 1) * 0.1
            return night
        }
        let normal = engine.score(snapshot(baseline + [Night(wristTemperature: 35)])).days.last?.recovery
        let feverish = engine.score(snapshot(baseline + [Night(wristTemperature: 36)])).days.last?.recovery
        #expect(normal?.contributors.first { $0.kind == .wristTemperature }?.effect == 0)
        #expect(feverish!.score < normal!.score)
    }

    @Test func risingOvernightHeartRateLowersRecovery() {
        let baseline = baselineNights(14).enumerated().map { index, night in
            var night = night
            night.heartRateRisePerHour = -1 + Double(index % 3 - 1) * 0.3
            return night
        }
        let falling = engine.score(snapshot(baseline + [Night(heartRateRisePerHour: -1)])).days.last
        let rising = engine.score(snapshot(baseline + [Night(heartRateRisePerHour: 1.5)])).days.last
        #expect(abs((falling?.overnightHRTrend ?? 0) + 1) < 0.01)
        #expect((rising?.recovery?.contributors.first { $0.kind == .overnightHeartRate }?.effect ?? 0) < 0)
        #expect(rising!.recovery!.score < falling!.recovery!.score)
    }

    // MARK: - Sleep

    @Test func sleepDebtCarriesOverButIsCapped() {
        let nights = (0..<10).map { _ in Night(sleepHours: 5) }
        let needs = engine.score(snapshot(nights)).days.compactMap { $0.sleep?.need }
        // Night 2 carries 55% of night 1's 2.5 h shortfall.
        #expect(abs(needs[1].debt - 0.55 * 2.5 * 3600) < 1)
        #expect(needs.map(\.debt) == needs.map(\.debt).sorted())
        #expect(needs.allSatisfy { $0.debt <= ScoringEngine.maximumSleepDebt })
    }

    @Test func oneFullNightClearsMostSleepDebt() {
        let nights = (0..<5).map { _ in Night(sleepHours: 5) } + [Night(sleepHours: 10), Night()]
        let needs = engine.score(snapshot(nights)).days.compactMap { $0.sleep?.need }
        #expect(needs[4].debt > 3600)
        #expect(needs[6].debt == 0)
    }

    @Test func sleepScoreRewardsRestorativeSleep() {
        let base = (asleep: 7.5 * 3600.0, need: 7.5 * 3600.0, efficiency: 0.92, consistency: 0.9)
        let good = ScoringEngine.sleepScore(asleep: base.asleep, need: base.need, efficiency: base.efficiency, hasStages: true,
                                            deep: 1.2 * 3600, rem: 1.8 * 3600, consistency: base.consistency)
        let noDeep = ScoringEngine.sleepScore(asleep: base.asleep, need: base.need, efficiency: base.efficiency, hasStages: true,
                                              deep: 0, rem: 3 * 3600, consistency: base.consistency)
        let unstaged = ScoringEngine.sleepScore(asleep: base.asleep, need: base.need, efficiency: base.efficiency, hasStages: false,
                                                deep: 0, rem: 0, consistency: base.consistency)
        #expect(good > 0.9)
        #expect(noDeep < good - 0.05)
        // Without stage data the restorative part drops out instead of counting as zero.
        #expect(unstaged > noDeep)
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
