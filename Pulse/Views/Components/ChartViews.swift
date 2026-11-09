import Charts
import SwiftUI

/// Sleep stages over the night, Awake at the top and Deep at the bottom.
struct HypnogramChart: View {
    let sleep: SleepSummary

    private var rows: [String] {
        sleep.hasStages ? ["Awake", "REM", "Core", "Deep"] : ["Awake", "Asleep"]
    }

    private func row(for stage: SleepStage) -> String {
        if sleep.hasStages && stage == .unspecified { return SleepStage.core.title }
        return stage.title
    }

    var body: some View {
        Chart(sleep.segments, id: \.self) { segment in
            RectangleMark(
                xStart: .value("Start", segment.start),
                xEnd: .value("End", segment.end),
                y: .value("Stage", row(for: segment.stage)),
                height: .ratio(0.8)
            )
            .foregroundStyle(Theme.color(for: segment.stage))
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .chartYScale(domain: rows)
        .chartXScale(domain: sleep.start...sleep.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) {
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisValueLabel()
            }
        }
        .frame(height: 170)
    }
}

/// Heart rate through the day with workouts shaded.
struct HeartRateChart: View {
    let day: DayMetrics
    let maxHeartRate: Double

    private var domainEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: day.date)!
    }

    var body: some View {
        let series = day.strain.heartRateSeries
        let ceiling = max(series.map(\.value).max() ?? 120, 120) + 10
        Chart {
            ForEach(day.strain.workouts) { workout in
                RectangleMark(xStart: .value("Start", workout.workout.start), xEnd: .value("End", workout.workout.end))
                    .foregroundStyle(Theme.strain.opacity(0.14))
            }
            RuleMark(y: .value("Zone 1", maxHeartRate * 0.5))
                .foregroundStyle(Color.white.opacity(0.2))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Strain starts here")
                        .font(.caption2)
                        .foregroundStyle(Theme.tertiaryText)
                }
            ForEach(series, id: \.date) { reading in
                AreaMark(x: .value("Time", reading.date), yStart: .value("Floor", 40), yEnd: .value("BPM", reading.value))
                    .foregroundStyle(LinearGradient(colors: [Theme.strain.opacity(0.35), Theme.strain.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", reading.date), y: .value("BPM", reading.value))
                    .foregroundStyle(Theme.strain)
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYScale(domain: 40...ceiling)
        .chartXScale(domain: day.date...domainEnd)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel()
            }
        }
        .frame(height: 190)
    }
}

/// Minutes in each heart-rate zone, hardest at the top.
struct ZoneBreakdown: View {
    let minutes: [Double]
    let maxHeartRate: Double

    var body: some View {
        let longest = max(minutes.max() ?? 1, 1)
        VStack(spacing: 12) {
            ForEach((0..<5).reversed(), id: \.self) { zone in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Theme.zoneNames[zone])
                            .font(.caption.weight(.semibold))
                        Text("\(Format.whole(maxHeartRate * (0.5 + Double(zone) * 0.1)))–\(Format.whole(maxHeartRate * (0.6 + Double(zone) * 0.1))) bpm")
                            .font(.caption2)
                            .foregroundStyle(Theme.tertiaryText)
                    }
                    .frame(width: 128, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.zoneColors[zone].gradient)
                            .frame(width: max(4, proxy.size.width * minutes[zone] / longest))
                    }
                    .frame(height: 10)
                    Text(Format.duration(minutes[zone] * 60))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }
}

/// Seven-day recovery bars, colored by zone.
struct RecoveryHistoryChart: View {
    let days: [DayMetrics]

    var body: some View {
        Chart(days) { day in
            if let recovery = day.recovery {
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Recovery", recovery.score), width: .ratio(0.55))
                    .foregroundStyle(Theme.color(for: recovery.zone).gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .annotation(position: .top) {
                        Text("\(recovery.score)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.secondaryText)
                    }
            }
        }
        .chartYScale(domain: 0...110)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .frame(height: 150)
    }
}

/// Seven-day strain bars.
struct StrainHistoryChart: View {
    let days: [DayMetrics]

    var body: some View {
        Chart(days) { day in
            BarMark(x: .value("Day", day.date, unit: .day), y: .value("Strain", day.strain.score), width: .ratio(0.55))
                .foregroundStyle(Theme.strain.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .annotation(position: .top) {
                    Text(Format.strain(day.strain.score))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                }
        }
        .chartYScale(domain: 0...23)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) {
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        }
        .frame(height: 150)
    }
}
