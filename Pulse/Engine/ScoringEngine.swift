import Foundation

nonisolated struct ScoringConfiguration: Hashable, Sendable {
    var sleepNeedBaseline: TimeInterval = 7.5 * 3600
    var maxHeartRateOverride: Double?
    var baselineWindowDays = 30
    /// Nights of HRV needed before a recovery score is shown.
    var minimumBaselineNights = 4
}

nonisolated enum MaxHeartRateSource: Hashable, Sendable {
    case custom, measured, age, standard

    var description: String {
        switch self {
        case .custom: "Set manually"
        case .measured: "Highest heart rate in your recent workouts"
        case .age: "Estimated from your age"
        case .standard: "Default estimate (add your birthday in Health for a better one)"
        }
    }
}

nonisolated struct ScoringResult: Sendable {
    /// Oldest first.
    var days: [DayMetrics]
    var maxHeartRate: Double
    var maxHeartRateSource: MaxHeartRateSource
}

/// Turns raw Health data into daily Recovery, Strain and Sleep scores.
///
/// All scores are relative to the user's own history, so the same HRV can mean different
/// things for different people.
nonisolated struct ScoringEngine {
    /// Heart rate below this fraction of max doesn't build strain (everyday movement).
    static let strainThreshold = 0.5
    /// Denominator of the logarithmic strain map. A full 24 hours in zone 5 is 5 × 1440 = 7200 TRIMP,
    /// so ln(7200 + 1) / ln(7201) = 1 puts that theoretical ceiling exactly at 21.
    static let strainLogDenominator = 7201.0

    var configuration = ScoringConfiguration()
    var calendar = Calendar.current

    func score(_ snapshot: HealthSnapshot) -> ScoringResult {
        let (maxHR, source) = maximumHeartRate(for: snapshot)
        var days: [DayMetrics] = []
        for day in dayStarts(in: snapshot.interval) {
            days.append(scoreDay(day, snapshot: snapshot, history: days, maxHR: maxHR))
        }
        return ScoringResult(days: days, maxHeartRate: maxHR, maxHeartRateSource: source)
    }

    // MARK: - Day

    private func scoreDay(_ day: Date, snapshot: HealthSnapshot, history: [DayMetrics], maxHR: Double) -> DayMetrics {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day)!
        let recent = Array(history.suffix(configuration.baselineWindowDays))
        let sessions = SleepSessions(day: day, samples: snapshot.sleep)

        // Overnight vitals come from the main sleep, or a generic overnight window without it.
        let night = sessions.main.map { DateInterval(start: $0.map(\.start).min()!, end: $0.map(\.end).max()!) }
        let overnight = night ?? DateInterval(start: day.addingTimeInterval(-3 * 3600), end: day.addingTimeInterval(10 * 3600))

        let hrv = snapshot.hrv.slice(from: overnight.start, to: overnight.end.addingTimeInterval(30 * 60)).meanValue
            ?? snapshot.hrv.slice(from: day.addingTimeInterval(-4 * 3600), to: day.addingTimeInterval(12 * 3600)).meanValue
        let restingHR = sleepingHeartRate(during: night, readings: snapshot.heartRate)
            ?? snapshot.restingHeartRate.slice(from: day, to: nextDay).meanValue
        let overnightHRTrend = overnightHeartRateTrend(during: night, readings: snapshot.heartRate)
        let respiratoryRate = snapshot.respiratoryRate.slice(from: overnight.start, to: overnight.end).meanValue
        let oxygen = snapshot.oxygenSaturation.slice(from: overnight.start, to: overnight.end).meanValue
        let temperature = snapshot.wristTemperature
            .slice(from: day.addingTimeInterval(SleepSessions.windowStartOffset), to: day.addingTimeInterval(SleepSessions.windowEndOffset))
            .meanValue

        let baselines = Baselines(
            hrv: Baseline(recent.compactMap(\.hrv)),
            restingHR: Baseline(recent.compactMap(\.restingHR)),
            respiratoryRate: Baseline(recent.compactMap(\.respiratoryRate)),
            oxygenSaturation: Baseline(recent.compactMap(\.oxygenSaturation)),
            wristTemperature: Baseline(recent.compactMap(\.wristTemperature)),
            sleepHours: Baseline(recent.compactMap { $0.sleep.map { $0.totalAsleep / 3600 } }),
            overnightHRTrend: Baseline(recent.compactMap(\.overnightHRTrend))
        )

        // Strain
        let dayEnd = min(nextDay, snapshot.interval.end)
        let dayReadings = snapshot.heartRate.slice(from: day, to: nextDay)
        let dayLoad = cardioLoad(dayReadings, until: dayEnd, maxHR: maxHR)
        let workouts = snapshot.workouts
            .filter { $0.start >= day && $0.start < nextDay }
            .map { workout in
                let readings = snapshot.heartRate.slice(from: workout.start, to: workout.end)
                let load = cardioLoad(readings, until: workout.end, maxHR: maxHR)
                return WorkoutStrain(workout: workout, strain: Self.strain(forLoad: load.load), averageHR: readings.meanValue, maxHR: readings.maxValue,
                                     zoneMinutes: load.zoneMinutes)
            }
        // The watch samples every few seconds during workouts but every few minutes otherwise,
        // so averaging 5-minute buckets keeps workouts from dominating the day's average.
        let series = Self.bucketed(dayReadings, every: 5 * 60)
        let strain = StrainSummary(
            score: Self.strain(forLoad: dayLoad.load),
            load: dayLoad.load,
            zoneMinutes: dayLoad.zoneMinutes,
            heartRateSeries: series,
            workouts: workouts,
            averageHR: series.meanValue,
            peakHR: dayReadings.maxValue
        )

        // Sleep
        let previousSleeps = history.compactMap(\.sleep)
        let need = sleepNeed(afterStrain: history.last?.strain.score, recentSleeps: previousSleeps)
        let sleep = sessions.main.map {
            sleepSummary(main: $0, naps: sessions.naps, need: need, previous: Array(previousSleeps.suffix(4)))
        }

        // Recovery
        let recovery = recoveryScore(hrv: hrv, restingHR: restingHR, respiratoryRate: respiratoryRate,
                                     sleepScore: sleep?.score, wristTemperature: temperature, overnightHRTrend: overnightHRTrend,
                                     history: recent, baselines: baselines)

        let tonightNeed = sleepNeed(afterStrain: strain.score, recentSleeps: previousSleeps + (sleep.map { [$0] } ?? []))

        return DayMetrics(
            date: day,
            sleep: sleep,
            recovery: recovery,
            baselineNights: recent.compactMap(\.hrv).count,
            strain: strain,
            strainTarget: recovery.map { Self.strainTarget(forRecovery: $0.score) },
            hrv: hrv,
            restingHR: restingHR,
            overnightHRTrend: overnightHRTrend,
            respiratoryRate: respiratoryRate,
            oxygenSaturation: oxygen,
            wristTemperature: temperature,
            steps: snapshot.dailySteps[day],
            activeEnergy: snapshot.dailyActiveEnergy[day],
            baselines: baselines,
            tonightNeed: tonightNeed,
            recommendedBedtime: recommendedBedtime(after: day, need: tonightNeed, recentSleeps: previousSleeps + (sleep.map { [$0] } ?? []))
        )
    }

    // MARK: - Recovery

    private func recoveryScore(hrv: Double?, restingHR: Double?, respiratoryRate: Double?, sleepScore: Double?,
                               wristTemperature: Double?, overnightHRTrend: Double?,
                               history: [DayMetrics], baselines: Baselines) -> RecoveryScore? {
        // HRV is log-normally distributed, so compare in log space.
        let logHistory = history.compactMap(\.hrv).filter { $0 > 0 }.map { log($0) }
        guard let hrv, hrv > 0, logHistory.count >= configuration.minimumBaselineNights,
              let logMean = logHistory.mean, let logSD = logHistory.standardDeviation else { return nil }

        var contributors = [
            RecoveryContributor(kind: .hrv, value: hrv, baseline: baselines.hrv,
                                effect: ((log(hrv) - logMean) / max(logSD, 0.08)).clamped(to: -3...3), weight: 0.5)
        ]
        if let restingHR, let baseline = baselines.restingHR, baseline.count >= configuration.minimumBaselineNights {
            let effect = (-(restingHR - baseline.mean) / max(baseline.standardDeviation, 1.5)).clamped(to: -3...3)
            contributors.append(RecoveryContributor(kind: .restingHR, value: restingHR, baseline: baseline, effect: effect, weight: 0.2))
        }
        if let sleepScore {
            let effect = ((sleepScore - 0.85) / 0.12).clamped(to: -3...1.5)
            contributors.append(RecoveryContributor(kind: .sleep, value: sleepScore * 100, baseline: nil, effect: effect, weight: 0.15))
        }
        if let respiratoryRate, let baseline = baselines.respiratoryRate, baseline.count >= configuration.minimumBaselineNights {
            // A lower-than-usual breathing rate isn't a strong positive, but a higher one is a warning sign.
            let effect = (-(respiratoryRate - baseline.mean) / max(baseline.standardDeviation, 0.5)).clamped(to: -3...1)
            contributors.append(RecoveryContributor(kind: .respiratoryRate, value: respiratoryRate, baseline: baseline, effect: effect, weight: 0.05))
        }
        if let wristTemperature, let baseline = baselines.wristTemperature, baseline.count >= configuration.minimumBaselineNights {
            // Symmetric: running hot or cold can both mean illness or overreaching. Only drift beyond
            // a normal night's spread counts, so the term never boosts recovery.
            let deviation = abs(wristTemperature - baseline.mean) / max(baseline.standardDeviation, 0.2)
            let effect = -max(0, deviation - 1).clamped(to: 0...3)
            contributors.append(RecoveryContributor(kind: .wristTemperature, value: wristTemperature, baseline: baseline, effect: effect, weight: 0.05))
        }
        if let overnightHRTrend, let baseline = baselines.overnightHRTrend, baseline.count >= configuration.minimumBaselineNights {
            // Heart rate normally falls through the night. Flatter or rising than usual (alcohol, a late meal,
            // illness, stress) holds recovery back.
            let effect = (-(overnightHRTrend - baseline.mean) / max(baseline.standardDeviation, 0.75)).clamped(to: -2...1)
            contributors.append(RecoveryContributor(kind: .overnightHeartRate, value: overnightHRTrend, baseline: baseline, effect: effect, weight: 0.05))
        }

        let totalWeight = contributors.reduce(0) { $0 + $1.weight }
        let composite = contributors.reduce(0) { $0 + $1.effect * $1.weight } / totalWeight
        // Logistic curve: an average night lands near 60%, one standard deviation better lands near 83%.
        let score = 100 / (1 + exp(-(1.25 * composite + 0.4)))
        return RecoveryScore(score: Int(score.rounded()).clamped(to: 1...99), contributors: contributors)
    }

    /// The strain range that builds fitness without digging a recovery hole.
    static func strainTarget(forRecovery recovery: Int) -> ClosedRange<Double> {
        let center = 7 + Double(recovery) * 0.1
        return (center - 1.5)...(center + 1.5)
    }

    // MARK: - Strain

    struct CardioLoad {
        var load = 0.0
        var zoneMinutes = Array(repeating: 0.0, count: 5)
    }

    /// Edwards TRIMP: each minute in heart-rate zone N (50–60% of max is zone 1, 90%+ is zone 5)
    /// contributes N points, so the load matches the zones the app shows.
    func cardioLoad(_ readings: ArraySlice<Reading>, until end: Date, maxHR: Double) -> CardioLoad {
        var result = CardioLoad()
        var index = readings.startIndex
        while index < readings.endIndex {
            let reading = readings[index]
            let next = readings.index(after: index)
            // Each reading represents the time until the next one, capped so watch-off gaps don't count.
            let nextDate = next < readings.endIndex ? readings[next].date : min(end, reading.date.addingTimeInterval(5 * 60))
            let minutes = nextDate.timeIntervalSince(reading.date).clamped(to: 0...(10 * 60)) / 60
            let fractionOfMax = reading.value / maxHR
            if fractionOfMax >= Self.strainThreshold {
                let zone = min(Int((fractionOfMax - 0.5) * 10), 4)
                result.zoneMinutes[zone] += minutes
                result.load += minutes * Double(zone + 1)
            }
            index = next
        }
        return result
    }

    /// Logarithmic map from TRIMP onto 0–21: strain = 21 · ln(load + 1) / ln(D).
    /// Early minutes move the score quickly and each extra point costs more, like perceived effort.
    static func strain(forLoad load: Double) -> Double {
        guard load > 0 else { return 0 }
        return min(StrainSummary.maximum, StrainSummary.maximum * log(load + 1) / log(strainLogDenominator))
    }

    private func maximumHeartRate(for snapshot: HealthSnapshot) -> (Double, MaxHeartRateSource) {
        if let custom = configuration.maxHeartRateOverride { return (custom, .custom) }
        let predicted = snapshot.profile.age.map { 208 - 0.7 * Double($0) }
        // A high percentile rather than the max, so a single sensor glitch doesn't skew everything.
        let observed = snapshot.heartRate.count > 500 ? snapshot.heartRate.map(\.value).percentile(0.9995) : nil

        let (value, source): (Double, MaxHeartRateSource) = switch (predicted, observed) {
        case let (predicted?, observed?): observed > predicted ? (observed, .measured) : (predicted, .age)
        case let (predicted?, nil): (predicted, .age)
        case let (nil, observed?) where observed > 190: (observed, .measured)
        default: (190, .standard)
        }
        return (value.clamped(to: 150...220), source)
    }

    // MARK: - Sleep

    private func sleepingHeartRate(during night: DateInterval?, readings: [Reading]) -> Double? {
        guard let night else { return nil }
        let values = readings.slice(from: night.start, to: night.end).map(\.value)
        // The 10th percentile approximates true resting HR while ignoring brief dips and artifacts.
        return values.count >= 5 ? values.percentile(0.1) : nil
    }

    /// Least-squares slope of heart rate across the main sleep, in bpm per hour. Negative is the healthy pattern.
    private func overnightHeartRateTrend(during night: DateInterval?, readings: [Reading]) -> Double? {
        guard let night, night.duration >= 3 * 3600 else { return nil }
        let points = readings.slice(from: night.start, to: night.end)
        guard points.count >= 12 else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(night.start) / 3600 }
        let ys = points.map(\.value)
        guard let meanX = xs.mean, let meanY = ys.mean else { return nil }
        let covariance = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let variance = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
        return variance > 0 ? covariance / variance : nil
    }

    /// Sleep debt carries over as a ledger: 55% of each night's unmet need (including debt it was
    /// already carrying) rolls forward, so a few short nights add up but one full night mostly clears them.
    static let sleepDebtCarry = 0.55
    static let maximumSleepDebt: TimeInterval = 2 * 3600

    private func sleepNeed(afterStrain strain: Double?, recentSleeps: [SleepSummary]) -> SleepNeed {
        let strainExtra = max(0, (strain ?? 0) - 10) / 11 * 45 * 60
        let debt = recentSleeps.last.map { Self.debt(after: $0) } ?? 0
        return SleepNeed(baseline: configuration.sleepNeedBaseline, strain: strainExtra, debt: debt)
    }

    static func debt(after sleep: SleepSummary) -> TimeInterval {
        let carried = sleepDebtCarry * max(0, sleep.need.total - sleep.totalAsleep)
        // Under ten minutes isn't worth acting on.
        return carried < 10 * 60 ? 0 : min(carried, maximumSleepDebt)
    }

    /// 0–1 sleep score: hours vs need (50%), efficiency (20%), deep + REM share (20%) and
    /// bed/wake consistency (10%). Missing parts drop out and the rest are re-weighted.
    static func sleepScore(asleep: TimeInterval, need: TimeInterval, efficiency: Double, hasStages: Bool,
                           deep: TimeInterval, rem: TimeInterval, consistency: Double?) -> Double {
        var parts: [(value: Double, weight: Double)] = [
            (min(1, asleep / max(need, 1)), 0.5),
            (efficiency.clamped(to: 0...1), 0.2),
        ]
        if hasStages, asleep > 0 {
            // ~50% deep + REM earns full credit; little deep sleep scales it down by up to half.
            let restorative = min(1, (deep + rem) / asleep / 0.5)
            let deepAdequacy = min(1, deep / asleep / 0.13)
            parts.append((restorative * (0.5 + 0.5 * deepAdequacy), 0.2))
        }
        if let consistency {
            parts.append((consistency.clamped(to: 0...1), 0.1))
        }
        let totalWeight = parts.reduce(0) { $0 + $1.weight }
        return parts.reduce(0) { $0 + $1.value * $1.weight } / totalWeight
    }

    private func sleepSummary(main: [SleepSample], naps: [[SleepSample]], need: SleepNeed, previous: [SleepSummary]) -> SleepSummary {
        let segments = main.sorted { $0.start < $1.start }
        let start = segments.first!.start
        let end = segments.map(\.end).max()!
        var stageDurations: [SleepStage: TimeInterval] = [:]
        for segment in segments {
            stageDurations[segment.stage, default: 0] += segment.duration
        }
        let asleep = SleepSessions.asleepTime(segments)
        let napTime = naps.reduce(0) { $0 + SleepSessions.asleepTime($1) }

        // Wake-ups: awake segments that have sleep on both sides.
        let firstAsleep = segments.firstIndex { $0.stage.isAsleep } ?? 0
        let lastAsleep = segments.lastIndex { $0.stage.isAsleep } ?? 0
        let disturbances = firstAsleep < lastAsleep
            ? segments[firstAsleep...lastAsleep].filter { $0.stage == .awake }.count
            : 0

        let consistency: Double? = previous.isEmpty ? nil : {
            let bedDiff = previous.map { abs(minutesSinceNoon(start) - minutesSinceNoon($0.start)) }.mean ?? 0
            let wakeDiff = previous.map { abs(minutesSinceNoon(end) - minutesSinceNoon($0.end)) }.mean ?? 0
            return (1 - (bedDiff + wakeDiff) / 2 / 120).clamped(to: 0...1)
        }()

        let hasStages = segments.contains { [.core, .deep, .rem].contains($0.stage) }
        let efficiency = (asleep / max(end.timeIntervalSince(start), 1)).clamped(to: 0...1)
        let score = Self.sleepScore(asleep: asleep + napTime, need: need.total, efficiency: efficiency, hasStages: hasStages,
                                    deep: stageDurations[.deep] ?? 0, rem: stageDurations[.rem] ?? 0, consistency: consistency)

        return SleepSummary(
            start: start,
            end: end,
            segments: segments,
            hasStages: hasStages,
            asleep: asleep,
            naps: naps.map { DateInterval(start: $0.map(\.start).min()!, end: $0.map(\.end).max()!) },
            napTime: napTime,
            stageDurations: stageDurations,
            need: need,
            score: score,
            performance: min(1, (asleep + napTime) / need.total),
            efficiency: efficiency,
            consistency: consistency,
            disturbances: disturbances
        )
    }

    private func recommendedBedtime(after day: Date, need: SleepNeed, recentSleeps: [SleepSummary]) -> Date? {
        let wakeTimes = recentSleeps.suffix(7).map { minutesSinceNoon($0.end) }
        guard let typicalWake = wakeTimes.mean else { return nil }
        // Wake times are measured from noon; tomorrow's wake is relative to noon today.
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let wake = noon.addingTimeInterval(typicalWake * 60)
        let fallAsleepBuffer: TimeInterval = 15 * 60
        return wake.addingTimeInterval(-need.total - fallAsleepBuffer)
    }

    /// Minutes since the most recent noon, so bedtimes either side of midnight compare sensibly.
    private func minutesSinceNoon(_ date: Date) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        return (minutes - 12 * 60 + 24 * 60).truncatingRemainder(dividingBy: 24 * 60)
    }

    // MARK: - Helpers

    private func dayStarts(in interval: DateInterval) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    static func bucketed(_ readings: ArraySlice<Reading>, every bucket: TimeInterval) -> [Reading] {
        var result: [Reading] = []
        var currentBucket: TimeInterval?
        var sum = 0.0
        var count = 0.0
        func flush() {
            if let currentBucket, count > 0 {
                result.append(Reading(date: Date(timeIntervalSinceReferenceDate: currentBucket + bucket / 2), value: sum / count))
            }
        }
        for reading in readings {
            let key = (reading.date.timeIntervalSinceReferenceDate / bucket).rounded(.down) * bucket
            if key != currentBucket {
                flush()
                currentBucket = key
                sum = 0
                count = 0
            }
            sum += reading.value
            count += 1
        }
        flush()
        return result
    }
}
