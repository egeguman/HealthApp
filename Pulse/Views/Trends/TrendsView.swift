import Charts
import SwiftUI

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30

    var id: Int { rawValue }
    var title: String { self == .week ? "7 Days" : "30 Days" }
}

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @State private var range = TrendRange.week

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Range", selection: $range) {
                        ForEach(TrendRange.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    let current = Array(model.days.suffix(range.rawValue))
                    let previous = Array(model.days.dropLast(range.rawValue).suffix(range.rawValue))
                    if current.isEmpty {
                        EmptyStateView(symbol: "chart.bar.xaxis", title: "No trends yet", message: "Trends appear once there's data from Health.")
                    } else {
                        TrendSummary(current: current, previous: previous, range: range)
                        TrendCharts(days: current, range: range)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .defaultScrollAnchor(LaunchOptions.scrollAnchor)
            .screenBackground()
            .navigationTitle("Trends")
        }
    }
}

private struct Averages {
    var recovery: Double?
    var strain: Double?
    var sleepHours: Double?
    var sleepNeedHours: Double?
    var hrv: Double?
    var restingHR: Double?

    init(_ days: [DayMetrics]) {
        recovery = days.compactMap { $0.recovery.map { Double($0.score) } }.mean
        strain = days.map(\.strain.score).mean
        sleepHours = days.compactMap { $0.sleep.map { $0.totalAsleep / 3600 } }.mean
        sleepNeedHours = days.compactMap { $0.sleep.map { $0.need.total / 3600 } }.mean
        hrv = days.compactMap(\.hrv).mean
        restingHR = days.compactMap(\.restingHR).mean
    }
}

private struct TrendSummary: View {
    let current: [DayMetrics]
    let previous: [DayMetrics]
    let range: TrendRange

    var body: some View {
        let now = Averages(current)
        let before = Averages(previous)
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                MetricTile(title: "Avg Recovery", symbol: "bolt.heart.fill", value: now.recovery.map(Format.whole) ?? "–", unit: "%",
                           comparison: change(now.recovery, before.recovery, higherIsBetter: true, format: Format.whole))
                MetricTile(title: "Avg Strain", symbol: "flame.fill", value: now.strain.map(Format.strain) ?? "–",
                           comparison: change(now.strain, before.strain, higherIsBetter: nil, format: Format.oneDecimal))
                MetricTile(title: "Avg Sleep", symbol: "moon.fill", value: now.sleepHours.map { Format.duration($0 * 3600) } ?? "–",
                           comparison: change(now.sleepHours, before.sleepHours, higherIsBetter: true, format: { Format.duration($0 * 3600) }))
                MetricTile(title: "Avg HRV", symbol: "waveform.path.ecg", value: now.hrv.map(Format.whole) ?? "–", unit: "ms",
                           comparison: change(now.hrv, before.hrv, higherIsBetter: true, format: Format.whole))
            }
            let takeaways = takeaways(now: now, before: before)
            if !takeaways.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Takeaways", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                    ForEach(takeaways, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Circle().fill(Theme.secondaryText).frame(width: 4, height: 4).padding(.top, 7)
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()
            }
        }
    }

    private func change(_ now: Double?, _ before: Double?, higherIsBetter: Bool?, format: (Double) -> String) -> MetricTile.Comparison? {
        guard let now, let before else { return nil }
        let diff = now - before
        let label = range == .week ? "last week" : "prior 30d"
        if abs(diff) < abs(before) * 0.02 { return .init(text: "Same as \(label)", isGood: nil) }
        return .init(text: "\(diff > 0 ? "▲" : "▼") \(format(abs(diff))) vs \(label)", isGood: higherIsBetter.map { $0 == (diff > 0) })
    }

    private func takeaways(now: Averages, before: Averages) -> [String] {
        var lines: [String] = []
        let period = range == .week ? "the week before" : "the previous 30 days"

        let zones = current.compactMap { $0.recovery?.zone }
        if !zones.isEmpty {
            let green = zones.filter { $0 == .green }.count
            let yellow = zones.filter { $0 == .yellow }.count
            let red = zones.filter { $0 == .red }.count
            lines.append("\(green) green, \(yellow) yellow and \(red) red recovery day\(zones.count == 1 ? "" : "s").")
        }
        if let hrv = now.hrv, let previous = before.hrv {
            let change = (hrv - previous) / previous
            if change >= 0.03 {
                lines.append("HRV is up \(Format.percent(change)) on \(period). Your body is adapting well.")
            } else if change <= -0.03 {
                lines.append("HRV is down \(Format.percent(-change)) on \(period). You may be building up fatigue, so consider an easier few days.")
            } else {
                lines.append("HRV is steady compared with \(period).")
            }
        }
        if let sleep = now.sleepHours, let need = now.sleepNeedHours {
            let gap = (need - sleep) * 3600
            lines.append(gap > 15 * 60
                         ? "You averaged \(Format.duration(sleep * 3600)) of sleep a night, \(Format.duration(gap)) less than you needed."
                         : "You averaged \(Format.duration(sleep * 3600)) of sleep a night, meeting your need. Nice.")
        }
        let overreached = current.filter { day in day.strainTarget.map { day.strain.score > $0.upperBound } ?? false }.count
        if overreached > 0 {
            lines.append("You went past your optimal strain on \(overreached) day\(overreached == 1 ? "" : "s"). Days like that need extra sleep to absorb.")
        }
        return lines
    }
}

private struct TrendCharts: View {
    let days: [DayMetrics]
    let range: TrendRange

    var body: some View {
        VStack(spacing: 16) {
            chartCard("Recovery", subtitle: "Green 67%+, yellow 34–66%, red under 34%") {
                Chart(days) { day in
                    if let recovery = day.recovery {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Recovery", recovery.score))
                            .foregroundStyle(Theme.color(for: recovery.zone).gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                .chartYScale(domain: 0...100)
            }

            chartCard("Strain", subtitle: "Bars are daily strain; marks show your optimal range") {
                Chart(days) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Strain", day.strain.score))
                        .foregroundStyle(Theme.strain.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if let target = day.strainTarget {
                        RectangleMark(x: .value("Day", day.date, unit: .day), yStart: .value("Low", target.lowerBound),
                                      yEnd: .value("High", target.upperBound), width: .ratio(0.9))
                            .foregroundStyle(Color.white.opacity(0.14))
                    }
                }
                .chartYScale(domain: 0...21)
            }

            chartCard("Sleep", subtitle: "Hours asleep vs what you needed (dashed)") {
                Chart(days) { day in
                    if let sleep = day.sleep {
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Hours", sleep.totalAsleep / 3600))
                            .foregroundStyle(Theme.sleep.gradient)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Need", sleep.need.total / 3600))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: 0...10)
            }

            chartCard("Heart rate variability", subtitle: "Higher is better. Dashed line is your 30-day average") {
                Chart(days) { day in
                    if let hrv = day.hrv {
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("HRV", hrv), series: .value("Series", "HRV"))
                            .foregroundStyle(Theme.green)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("HRV", hrv))
                            .foregroundStyle(Theme.green)
                            .symbolSize(range == .week ? 40 : 14)
                    }
                    if let baseline = day.baselines.hrv {
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("Average", baseline.mean), series: .value("Series", "Average"))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
            }

            chartCard("Resting heart rate", subtitle: "Lower is better. Measured while you sleep") {
                Chart(days) { day in
                    if let rhr = day.restingHR {
                        LineMark(x: .value("Day", day.date, unit: .day), y: .value("RHR", rhr))
                            .foregroundStyle(Theme.red)
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Day", day.date, unit: .day), y: .value("RHR", rhr))
                            .foregroundStyle(Theme.red)
                            .symbolSize(range == .week ? 40 : 14)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
            }
        }
    }

    private func chartCard(_ title: String, subtitle: String, @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(Theme.tertiaryText)
            }
            chart()
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) {
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel(format: range == .week ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel()
                    }
                }
                .frame(height: 160)
        }
        .card()
    }
}
