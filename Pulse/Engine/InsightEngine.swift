import Foundation

nonisolated struct Insight: Identifiable, Hashable, Sendable {
    enum Tone: Hashable, Sendable {
        case positive, neutral, caution, negative
    }

    let id: String
    let symbol: String
    let title: String
    let message: String
    let tone: Tone
}

/// Plain-language explanations of what the numbers mean and what to do about them.
nonisolated enum InsightEngine {
    static func headline(for day: DayMetrics, minimumNights: Int = 4) -> Insight {
        guard let recovery = day.recovery else {
            if day.hrv != nil && day.baselineNights < minimumNights {
                let remaining = minimumNights - day.baselineNights
                return Insight(id: "headline", symbol: "dial.medium", title: "Learning your baseline",
                               message: "Recovery compares you to your own normal. Wear your Apple Watch to bed for \(remaining) more night\(remaining == 1 ? "" : "s") to unlock it.",
                               tone: .neutral)
            }
            return Insight(id: "headline", symbol: "applewatch", title: "No recovery data yet",
                           message: "Recovery needs an overnight HRV reading. Wear your Apple Watch to bed with Sleep Focus on and check back in the morning.",
                           tone: .neutral)
        }
        let target = day.strainTarget.map(Format.strainRange) ?? ""
        switch recovery.zone {
        case .green:
            return Insight(id: "headline", symbol: "bolt.heart.fill", title: "You're recovered. Go for it.",
                           message: "Your body is primed for strain. A day in the \(target) range will build fitness.", tone: .positive)
        case .yellow:
            return Insight(id: "headline", symbol: "figure.walk.motion", title: "Moderately recovered",
                           message: "Your body is maintaining. Moderate training is fine. Aim for \(target) strain and don't go all-out.", tone: .caution)
        case .red:
            return Insight(id: "headline", symbol: "bed.double.fill", title: "Prioritize rest today",
                           message: "Your body is under stress. Keep strain in the \(target) range, stay hydrated, and get to bed early.", tone: .negative)
        }
    }

    static func insights(for day: DayMetrics, isToday: Bool, now: Date = .now) -> [Insight] {
        var result: [Insight] = []

        if isToday, let target = day.strainTarget {
            let strain = day.strain.score
            if strain < target.lowerBound {
                result.append(Insight(id: "strain", symbol: "flame", title: "\(Format.strain(target.lowerBound - strain)) strain to your target",
                                      message: "You're at \(Format.strain(strain)). A workout would get you into today's \(Format.strainRange(target)) range.", tone: .neutral))
            } else if strain <= target.upperBound {
                result.append(Insight(id: "strain", symbol: "checkmark.seal.fill", title: "You've hit your strain target",
                                      message: "You're at \(Format.strain(strain)), right in today's optimal range. Anything more is optional.", tone: .positive))
            } else {
                result.append(Insight(id: "strain", symbol: "exclamationmark.triangle.fill", title: "Past your optimal strain",
                                      message: "At \(Format.strain(strain)), extra effort now adds more fatigue than fitness. Plan for more sleep tonight.", tone: .caution))
            }
        }

        if let hrv = day.hrv, let baseline = day.baselines.hrv {
            let change = (hrv - baseline.mean) / baseline.mean
            let values = "\(Format.whole(hrv)) ms vs your usual \(Format.whole(baseline.mean)) ms."
            if change >= 0.05 {
                result.append(Insight(id: "hrv", symbol: "waveform.path.ecg", title: "HRV is \(Format.percent(change)) above normal",
                                      message: "\(values) Higher HRV means your nervous system is relaxed and recovered.", tone: .positive))
            } else if change <= -0.05 {
                result.append(Insight(id: "hrv", symbol: "waveform.path.ecg", title: "HRV is \(Format.percent(-change)) below normal",
                                      message: "\(values) Common causes: hard training, alcohol, late meals, stress or getting sick.", tone: change <= -0.15 ? .negative : .caution))
            }
        }

        if let rhr = day.restingHR, let baseline = day.baselines.restingHR {
            let diff = rhr - baseline.mean
            if diff >= 3 {
                result.append(Insight(id: "rhr", symbol: "heart.fill", title: "Resting heart rate is up \(Format.whole(diff)) bpm",
                                      message: "\(Format.whole(rhr)) bpm overnight vs your usual \(Format.whole(baseline.mean)). Your heart is working harder to recover.", tone: .caution))
            } else if diff <= -2 {
                result.append(Insight(id: "rhr", symbol: "heart.fill", title: "Resting heart rate is low",
                                      message: "\(Format.whole(rhr)) bpm overnight, \(Format.whole(-diff)) below your usual. A sign of good recovery.", tone: .positive))
            }
        }

        if let rate = day.respiratoryRate, let baseline = day.baselines.respiratoryRate,
           rate - baseline.mean >= max(2 * baseline.standardDeviation, 1) {
            result.append(Insight(id: "resp", symbol: "lungs.fill", title: "Breathing rate is elevated",
                                  message: "\(Format.oneDecimal(rate)) breaths/min while asleep vs your usual \(Format.oneDecimal(baseline.mean)). This can be an early sign of illness.", tone: .negative))
        }

        if let delta = day.wristTemperatureDelta, abs(delta) >= 0.5 {
            result.append(Insight(id: "temp", symbol: "thermometer.medium", title: "Wrist temperature \(Format.signedTemperature(delta))",
                                  message: "Your sleeping temperature is off your baseline. Illness, alcohol, a warm room or your cycle can all cause this.", tone: .caution))
        }

        if let sleep = day.sleep {
            let shortfall = sleep.need.total - sleep.totalAsleep
            if shortfall <= 10 * 60 {
                result.append(Insight(id: "sleep", symbol: "moon.stars.fill", title: "You met your sleep need",
                                      message: "\(Format.duration(sleep.totalAsleep)) of sleep against a need of \(Format.duration(sleep.need.total)).", tone: .positive))
            } else {
                result.append(Insight(id: "sleep", symbol: "moon.zzz.fill", title: "\(Format.duration(shortfall)) short on sleep",
                                      message: "You slept \(Format.duration(sleep.totalAsleep)) but needed \(Format.duration(sleep.need.total)). Shortfalls add up and lower tomorrow's recovery.",
                                      tone: shortfall > 90 * 60 ? .negative : .caution))
            }
        } else {
            result.append(Insight(id: "sleep", symbol: "moon.zzz", title: "No sleep recorded",
                                  message: "Wear your Apple Watch to bed and set up a Sleep schedule in the Health app to track sleep stages.", tone: .neutral))
        }

        if isToday, let bedtime = day.recommendedBedtime, bedtime > now {
            result.append(Insight(id: "bedtime", symbol: "bed.double.fill", title: "Aim for bed by \(Format.time(bedtime))",
                                  message: "That gets you the \(Format.duration(day.tonightNeed.total)) of sleep you'll need tonight, based on today's strain and recent sleep.", tone: .neutral))
        }

        return result
    }
}
