import Foundation

/// A single timestamped measurement: heart rate in bpm, HRV in ms, SpO₂ in %, etc.
nonisolated struct Reading: Hashable, Sendable {
    let date: Date
    let value: Double
}

nonisolated enum SleepStage: Int, CaseIterable, Sendable, Hashable {
    case awake
    case rem
    case core
    case deep
    /// Asleep, but the source didn't record stages (older watches, third-party apps).
    case unspecified
    case inBed

    var isAsleep: Bool {
        switch self {
        case .rem, .core, .deep, .unspecified: true
        case .awake, .inBed: false
        }
    }

    var title: String {
        switch self {
        case .awake: "Awake"
        case .rem: "REM"
        case .core: "Core"
        case .deep: "Deep"
        case .unspecified: "Asleep"
        case .inBed: "In Bed"
        }
    }
}

nonisolated struct SleepSample: Hashable, Sendable {
    let start: Date
    let end: Date
    let stage: SleepStage
    /// Bundle identifier of the app/device that recorded the sample, used to avoid double-counting.
    let source: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

nonisolated struct WorkoutRecord: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let end: Date
    let activeEnergy: Double?
    let distance: Double?

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

nonisolated enum BiologicalSex: String, Codable, Sendable {
    case female, male, unknown
}

nonisolated struct UserProfile: Hashable, Sendable {
    var age: Int?
    var sex: BiologicalSex = .unknown
}

/// Everything read from Health for a date range, already converted to plain values.
nonisolated struct HealthSnapshot: Sendable {
    var interval: DateInterval
    var heartRate: [Reading] = []
    var hrv: [Reading] = []
    var restingHeartRate: [Reading] = []
    var respiratoryRate: [Reading] = []
    /// Percent (0–100).
    var oxygenSaturation: [Reading] = []
    /// Absolute sleeping wrist temperature in °C.
    var wristTemperature: [Reading] = []
    var sleep: [SleepSample] = []
    var workouts: [WorkoutRecord] = []
    /// Keyed by start of day.
    var dailySteps: [Date: Double] = [:]
    /// Keyed by start of day, kcal.
    var dailyActiveEnergy: [Date: Double] = [:]
    var profile = UserProfile()
}

extension Array where Element == Reading {
    /// Readings whose date falls in `[start, end)`. Requires the array to be sorted by date.
    nonisolated func slice(from start: Date, to end: Date) -> ArraySlice<Reading> {
        let lower = firstIndex(notBefore: start)
        let upper = firstIndex(notBefore: end)
        return self[lower..<Swift.max(lower, upper)]
    }

    nonisolated private func firstIndex(notBefore date: Date) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if self[mid].date < date { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
