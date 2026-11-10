import Foundation

nonisolated enum RecoveryZone: Hashable, Sendable {
    case green, yellow, red

    init(score: Int) {
        switch score {
        case 67...: self = .green
        case 34...: self = .yellow
        default: self = .red
        }
    }

    var title: String {
        switch self {
        case .green: "Ready to perform"
        case .yellow: "Maintaining"
        case .red: "Prioritize rest"
        }
    }
}

/// Mean and spread of a metric over the trailing baseline window.
nonisolated struct Baseline: Hashable, Sendable {
    let mean: Double
    let standardDeviation: Double
    let count: Int

    init?(_ values: [Double]) {
        guard values.count >= 2, let mean = values.mean, let sd = values.standardDeviation else { return nil }
        self.mean = mean
        self.standardDeviation = sd
        self.count = values.count
    }

    /// The "normal" band most nights fall into.
    var typicalRange: ClosedRange<Double> {
        (mean - standardDeviation)...(mean + standardDeviation)
    }
}

nonisolated struct Baselines: Hashable, Sendable {
    var hrv: Baseline?
    var restingHR: Baseline?
    var respiratoryRate: Baseline?
    var oxygenSaturation: Baseline?
    var wristTemperature: Baseline?
    /// Hours of sleep per night.
    var sleepHours: Baseline?
    /// Overnight heart-rate slope, bpm per hour.
    var overnightHRTrend: Baseline?
}

nonisolated struct RecoveryContributor: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case hrv, restingHR, sleep, respiratoryRate, wristTemperature, overnightHeartRate
    }

    var id: Kind { kind }
    let kind: Kind
    let value: Double
    let baseline: Baseline?
    /// Standardized effect on recovery. Positive values push recovery up.
    let effect: Double
    let weight: Double
}

nonisolated struct RecoveryScore: Hashable, Sendable {
    let score: Int
    let contributors: [RecoveryContributor]

    var zone: RecoveryZone { RecoveryZone(score: score) }
}

nonisolated struct SleepNeed: Hashable, Sendable {
    let baseline: TimeInterval
    /// Extra sleep needed to recover from the previous day's strain.
    let strain: TimeInterval
    /// Extra sleep to pay back recent shortfalls.
    let debt: TimeInterval

    var total: TimeInterval { baseline + strain + debt }
}

nonisolated struct SleepSummary: Hashable, Sendable {
    let start: Date
    let end: Date
    /// Samples from the main sleep session, sorted by start.
    let segments: [SleepSample]
    let hasStages: Bool
    let asleep: TimeInterval
    let naps: [DateInterval]
    let napTime: TimeInterval
    let stageDurations: [SleepStage: TimeInterval]
    let need: SleepNeed
    /// Overall sleep score, 0–1: hours vs need, efficiency, restorative sleep and consistency.
    let score: Double
    /// Share of sleep need achieved, 0–1.
    let performance: Double
    /// Time asleep divided by time in bed, 0–1.
    let efficiency: Double
    /// How closely bed and wake times match recent nights, 0–1.
    let consistency: Double?
    /// Times you woke up during the night.
    let disturbances: Int

    var totalAsleep: TimeInterval { asleep + napTime }
    var timeInBed: TimeInterval { end.timeIntervalSince(start) }
    var restorative: TimeInterval { duration(of: .deep) + duration(of: .rem) }

    func duration(of stage: SleepStage) -> TimeInterval {
        stageDurations[stage] ?? 0
    }
}

nonisolated struct WorkoutStrain: Identifiable, Hashable, Sendable {
    let workout: WorkoutRecord
    let strain: Double
    let averageHR: Double?
    let maxHR: Double?
    /// Minutes in each heart-rate zone during the workout.
    var zoneMinutes: [Double] = Array(repeating: 0, count: 5)

    var id: UUID { workout.id }
}

nonisolated struct StrainSummary: Hashable, Sendable {
    static let maximum = 21.0

    /// 0–21, logarithmic like the Borg scale: each point is harder to earn than the last.
    let score: Double
    /// Raw cardiovascular load (Edwards TRIMP: zone-weighted minutes).
    let load: Double
    /// Minutes in each heart-rate zone (50–60%, 60–70%, 70–80%, 80–90%, 90–100% of max).
    let zoneMinutes: [Double]
    /// 5-minute averages for charting.
    let heartRateSeries: [Reading]
    let workouts: [WorkoutStrain]
    let averageHR: Double?
    let peakHR: Double?
}

nonisolated struct DayMetrics: Identifiable, Hashable, Sendable {
    let date: Date
    var sleep: SleepSummary?
    var recovery: RecoveryScore?
    /// Nights with HRV available in the baseline window, so the UI can explain calibration.
    var baselineNights: Int
    var strain: StrainSummary
    var strainTarget: ClosedRange<Double>?
    var hrv: Double?
    var restingHR: Double?
    /// How heart rate changed across the night, bpm per hour. Falling (negative) is the healthy pattern.
    var overnightHRTrend: Double?
    var respiratoryRate: Double?
    var oxygenSaturation: Double?
    var wristTemperature: Double?
    var steps: Double?
    var activeEnergy: Double?
    var baselines: Baselines
    /// What tonight's sleep should be, given today's strain and recent sleep debt.
    var tonightNeed: SleepNeed
    var recommendedBedtime: Date?

    var id: Date { date }

    var wristTemperatureDelta: Double? {
        guard let wristTemperature, let baseline = baselines.wristTemperature else { return nil }
        return wristTemperature - baseline.mean
    }
}
