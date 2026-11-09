import Foundation

/// Picks out the night's main sleep and any naps from raw Health samples.
///
/// Health often holds overlapping sleep data from several sources (Apple Watch stages, the iPhone's
/// bedtime schedule, third-party apps). To avoid double-counting, a single source is used per day:
/// the one with stage data and the most time asleep.
nonisolated struct SleepSessions {
    /// Sleep is attributed to the day it ends on, within this window around midnight.
    static let windowStartOffset: TimeInterval = -6 * 3600   // 6 PM the previous evening
    static let windowEndOffset: TimeInterval = 18 * 3600     // 6 PM on the day
    /// A gap longer than this splits samples into separate sessions.
    static let sessionGap: TimeInterval = 60 * 60
    static let minimumNap: TimeInterval = 10 * 60

    let main: [SleepSample]?
    let naps: [[SleepSample]]

    init(day: Date, samples: [SleepSample]) {
        let windowStart = day.addingTimeInterval(Self.windowStartOffset)
        let windowEnd = day.addingTimeInterval(Self.windowEndOffset)
        let candidates = samples.filter { $0.stage != .inBed && $0.end > windowStart && $0.end <= windowEnd }

        let bySource = Dictionary(grouping: candidates, by: \.source)
        guard let chosen = bySource.values.max(by: { Self.rank($0) < Self.rank($1) }) else {
            main = nil
            naps = []
            return
        }

        var sessions: [[SleepSample]] = []
        var sessionEnd = Date.distantPast
        for sample in chosen.sorted(by: { $0.start < $1.start }) {
            if !sessions.isEmpty, sample.start.timeIntervalSince(sessionEnd) <= Self.sessionGap {
                sessions[sessions.count - 1].append(sample)
                sessionEnd = max(sessionEnd, sample.end)
            } else {
                sessions.append([sample])
                sessionEnd = sample.end
            }
        }
        sessions.removeAll { Self.asleepTime($0) == 0 }

        guard let mainIndex = sessions.indices.max(by: { Self.asleepTime(sessions[$0]) < Self.asleepTime(sessions[$1]) }) else {
            main = nil
            naps = []
            return
        }
        main = sessions[mainIndex]
        naps = sessions.indices
            .filter { $0 != mainIndex && Self.asleepTime(sessions[$0]) >= Self.minimumNap }
            .map { sessions[$0] }
    }

    static func asleepTime(_ samples: [SleepSample]) -> TimeInterval {
        samples.filter(\.stage.isAsleep).reduce(0) { $0 + $1.duration }
    }

    private static func rank(_ samples: [SleepSample]) -> Double {
        let hasStages = samples.contains { [.core, .deep, .rem].contains($0.stage) }
        return (hasStages ? 1_000_000 : 0) + asleepTime(samples)
    }
}
