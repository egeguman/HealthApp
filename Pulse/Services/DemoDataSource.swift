import Foundation

/// Synthetic Apple Watch data for trying the app (and for the simulator, which has no Health data).
/// It goes through exactly the same scoring pipeline as real data.
struct DemoDataSource: HealthDataSource {
    func requestAuthorization() async throws {}

    func fetchSnapshot(in interval: DateInterval) async throws -> HealthSnapshot {
        DemoDataGenerator(now: interval.end).snapshot(for: interval)
    }
}

nonisolated struct DemoDataGenerator {
    var now: Date
    var calendar = Calendar.current

    private struct PlannedWorkout {
        let name: String
        let symbol: String
        let minutes: Double
        let averageHR: Double
        let kcalPerMinute: Double
        let metersPerMinute: Double?
        let intervals: Bool
    }

    private static let source = "com.apple.health.demo"
    private static let baseHRV = 58.0
    private static let baseRestingHR = 53.0
    private static let baseRespiratoryRate = 14.6
    private static let baseWristTemperature = 35.9

    func snapshot(for interval: DateInterval) -> HealthSnapshot {
        var rng = SeededGenerator(seed: 7)
        var snapshot = HealthSnapshot(interval: interval)
        snapshot.profile = UserProfile(age: 29, sex: .male)

        let firstDay = calendar.startOfDay(for: interval.start)
        let today = calendar.startOfDay(for: now)
        let dayCount = calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0
        var previousIntensity = 0.5

        for offset in 0...dayCount {
            let day = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let daysAgo = dayCount - offset
            let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
            let sick = (9...11).contains(daysAgo)

            // MARK: Night ending this morning
            let weekendNight = weekday == 7 || weekday == 1
            var bedtime = day.addingTimeInterval(-60 * 60 + rng.normal(0, 25 * 60) + (weekendNight ? 50 * 60 : 0))
            var hours = rng.normal(7.3, 0.55).clamped(to: 5.4...8.8) + (weekendNight ? 0.4 : 0) + (sick ? 0.6 : 0)
            switch daysAgo {
            case 0: hours = 7.9; bedtime = day.addingTimeInterval(-62 * 60)
            case 1: hours = 6.1
            default: break
            }
            let night = sleepStages(from: bedtime, asleepHours: hours, rng: &rng)
            snapshot.sleep += night.samples
            let wake = night.end

            var quality = rng.normal(0, 0.07) - (previousIntensity - 0.5) * 0.14 + (hours - 7.3) * 0.06
            if sick { quality -= 0.32 }
            if daysAgo == 0 { quality = 0.13 }
            let nightHRV = Self.baseHRV * exp(quality)
            let nightRestingHR = Self.baseRestingHR - quality * 16 + (sick ? 4 : 0)

            var time = bedtime.addingTimeInterval(rng.uniform(60, 240))
            while time < wake {
                let progress = time.timeIntervalSince(bedtime) / wake.timeIntervalSince(bedtime)
                let dip = sin(progress * .pi) * 3   // heart rate bottoms out mid-night
                snapshot.heartRate.append(Reading(date: time, value: nightRestingHR + 4 - dip + rng.uniform(-1.5, 3)))
                time.addTimeInterval(rng.uniform(240, 420))
            }
            for i in 0..<4 {
                let at = bedtime.addingTimeInterval(Double(i + 1) * hours * 3600 / 5)
                snapshot.hrv.append(Reading(date: at, value: nightHRV * rng.uniform(0.88, 1.12)))
            }
            for i in 0..<3 {
                let at = bedtime.addingTimeInterval(Double(i + 1) * hours * 3600 / 4)
                snapshot.respiratoryRate.append(Reading(date: at, value: Self.baseRespiratoryRate + (sick ? 2.4 : 0) + rng.normal(0, 0.25)))
                snapshot.oxygenSaturation.append(Reading(date: at, value: rng.uniform(95.5, 98.8)))
            }
            snapshot.wristTemperature.append(Reading(date: wake, value: Self.baseWristTemperature + rng.normal(0, 0.12) + (sick ? 0.7 : 0)))
            snapshot.restingHeartRate.append(Reading(date: day.addingTimeInterval(12 * 3600), value: nightRestingHR + 3))

            // MARK: Daytime
            let nextBedtime = calendar.date(byAdding: .day, value: 1, to: day)!.addingTimeInterval(-60 * 60)
            let dayEnd = min(nextBedtime, now)
            guard wake < dayEnd else { continue }

            var workout = plannedWorkout(weekday: weekday)
            if sick || (daysAgo > 0 && rng.uniform(0, 1) < 0.12) { workout = nil }
            let morning = daysAgo == 0 || offset.isMultiple(of: 2)
            let workoutStart = day.addingTimeInterval((morning ? 7.25 : 18) * 3600 + rng.uniform(-15, 20) * 60)
            var workoutInterval: DateInterval?
            if let plan = workout {
                let end = workoutStart.addingTimeInterval(plan.minutes * 60)
                if end <= now {
                    workoutInterval = DateInterval(start: workoutStart, end: end)
                    snapshot.workouts.append(WorkoutRecord(
                        id: UUID(), name: plan.name, symbol: plan.symbol, start: workoutStart, end: end,
                        activeEnergy: plan.minutes * plan.kcalPerMinute * rng.uniform(0.9, 1.1),
                        distance: plan.metersPerMinute.map { $0 * plan.minutes * rng.uniform(0.93, 1.07) }))
                    snapshot.heartRate += workoutHeartRate(plan, from: workoutStart, to: end, rng: &rng)
                } else {
                    workout = nil
                }
            }

            // Background readings every few minutes, with a few walks sprinkled through the day.
            let walks = (0..<Int(rng.uniform(2, 5))).map { _ in
                let start = wake.addingTimeInterval(rng.uniform(1, 14) * 3600)
                return DateInterval(start: start, duration: rng.uniform(10, 25) * 60)
            }
            time = wake.addingTimeInterval(rng.uniform(60, 300))
            while time < dayEnd {
                if workoutInterval?.contains(time) != true {
                    let walking = walks.contains { $0.contains(time) }
                    let value = walking ? rng.uniform(98, 116) : rng.normal(70, 6) + (sick ? 6 : 0)
                    snapshot.heartRate.append(Reading(date: time, value: value))
                }
                time.addTimeInterval(rng.uniform(240, 420))
            }

            let elapsed = (dayEnd.timeIntervalSince(wake) / nextBedtime.timeIntervalSince(wake)).clamped(to: 0...1)
            let workoutSteps: Double = switch workout?.name {
            case "Running": 6500
            case "Walking": 5500
            default: 0
            }
            snapshot.dailySteps[day] = (rng.normal(6500, 1400) + workoutSteps) * elapsed
            let workoutEnergy = snapshot.workouts.last.flatMap { $0.start >= day ? $0.activeEnergy : nil } ?? 0
            snapshot.dailyActiveEnergy[day] = rng.normal(380, 60) * elapsed + workoutEnergy

            previousIntensity = workout.map { ($0.averageHR - 100) / 60 * min($0.minutes / 60, 1.5) } ?? 0.15
        }

        // Nothing from the future: last night may still be in progress.
        snapshot.heartRate.sort { $0.date < $1.date }
        snapshot.heartRate.removeAll { $0.date > now }
        snapshot.sleep.removeAll { $0.end > now }
        snapshot.hrv.removeAll { $0.date > now }
        snapshot.respiratoryRate.removeAll { $0.date > now }
        snapshot.oxygenSaturation.removeAll { $0.date > now }
        snapshot.wristTemperature.removeAll { $0.date > now }
        snapshot.restingHeartRate.removeAll { $0.date > now }
        return snapshot
    }

    private func plannedWorkout(weekday: Int) -> PlannedWorkout? {
        switch weekday {
        case 2: PlannedWorkout(name: "Strength Training", symbol: "figure.strengthtraining.traditional", minutes: 55, averageHR: 124, kcalPerMinute: 7, metersPerMinute: nil, intervals: true)
        case 3: PlannedWorkout(name: "Running", symbol: "figure.run", minutes: 46, averageHR: 154, kcalPerMinute: 11.5, metersPerMinute: 182, intervals: false)
        case 5: PlannedWorkout(name: "HIIT", symbol: "figure.highintensity.intervaltraining", minutes: 36, averageHR: 156, kcalPerMinute: 12, metersPerMinute: nil, intervals: true)
        case 6: PlannedWorkout(name: "Walking", symbol: "figure.walk", minutes: 50, averageHR: 106, kcalPerMinute: 4.8, metersPerMinute: 85, intervals: false)
        case 7: PlannedWorkout(name: "Cycling", symbol: "figure.outdoor.cycle", minutes: 95, averageHR: 141, kcalPerMinute: 10, metersPerMinute: 440, intervals: false)
        case 1: PlannedWorkout(name: "Running", symbol: "figure.run", minutes: 62, averageHR: 146, kcalPerMinute: 11, metersPerMinute: 170, intervals: false)
        default: nil
        }
    }

    private func workoutHeartRate(_ plan: PlannedWorkout, from start: Date, to end: Date, rng: inout SeededGenerator) -> [Reading] {
        var readings: [Reading] = []
        var time = start
        var value = 95.0
        let total = end.timeIntervalSince(start)
        while time < end {
            let elapsed = time.timeIntervalSince(start)
            var target = plan.averageHR
            if elapsed < 5 * 60 {
                target = 95 + (plan.averageHR - 95) * elapsed / (5 * 60)
            } else if total - elapsed < 4 * 60 {
                target = plan.averageHR - 25
            } else if plan.intervals {
                target += (elapsed.truncatingRemainder(dividingBy: 240) < 150) ? 14 : -18
            } else {
                target += sin(elapsed / 400) * 6
            }
            value += (target - value) * 0.25 + rng.normal(0, 2)
            readings.append(Reading(date: time, value: value))
            time.addTimeInterval(10)
        }
        return readings
    }

    /// Roughly 90-minute cycles: deep sleep front-loaded, REM growing toward morning.
    private func sleepStages(from bedtime: Date, asleepHours: Double, rng: inout SeededGenerator) -> (samples: [SleepSample], end: Date) {
        var samples: [SleepSample] = []
        var time = bedtime
        var asleep: TimeInterval = 0
        let target = asleepHours * 3600

        func add(_ stage: SleepStage, minutes: Double) {
            guard minutes > 0.5 else { return }
            var duration = minutes * 60
            if stage.isAsleep { duration = min(duration, target - asleep) }
            guard duration > 0 else { return }
            samples.append(SleepSample(start: time, end: time.addingTimeInterval(duration), stage: stage, source: Self.source))
            time.addTimeInterval(duration)
            if stage.isAsleep { asleep += duration }
        }

        add(.awake, minutes: rng.uniform(3, 12))
        var cycle = 0
        while asleep < target {
            let early = cycle < 2
            let late = cycle >= 3
            add(.core, minutes: rng.uniform(15, 30))
            add(.deep, minutes: early ? rng.uniform(22, 38) : late ? rng.uniform(0, 7) : rng.uniform(8, 18))
            add(.core, minutes: rng.uniform(10, 25))
            add(.rem, minutes: early ? rng.uniform(6, 14) : rng.uniform(18, 32))
            if asleep < target, rng.uniform(0, 1) < 0.45 {
                add(.awake, minutes: rng.uniform(1, 5))
            }
            cycle += 1
        }
        add(.awake, minutes: rng.uniform(2, 8))
        return (samples, time)
    }
}

/// Deterministic RNG so the demo looks the same every launch.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func uniform(_ lower: Double, _ upper: Double) -> Double {
        Double.random(in: lower..<upper, using: &self)
    }

    /// Box–Muller transform.
    mutating func normal(_ mean: Double, _ sd: Double) -> Double {
        let u1 = max(uniform(0, 1), .leastNonzeroMagnitude)
        let u2 = uniform(0, 1)
        return mean + sd * (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
