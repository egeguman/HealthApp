import Charts
import SwiftUI

/// A WHOOP-style overview of everything completed on the selected day: totals, a timeline, each activity, and the week so far.
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    DayHeader()
                    if let day = model.selectedDay {
                        ActivityDayContent(day: day)
                    } else if model.isLoading {
                        ProgressView()
                            .padding(.top, 160)
                    } else {
                        EmptyStateView(symbol: "figure.run", title: "No activity yet",
                                       message: "Activities appear once your Apple Watch has synced with Health.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .defaultScrollAnchor(LaunchOptions.scrollAnchor)
            .screenBackground()
            .refreshable { await model.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .recovery(let date): RecoveryDetailView(date: date)
                case .strain(let date): StrainDetailView(date: date)
                case .sleep(let date): SleepDetailView(date: date)
                }
            }
        }
    }
}

private struct ActivityDayContent: View {
    @Environment(AppModel.self) private var model
    let day: DayMetrics

    private var workouts: [WorkoutStrain] {
        day.strain.workouts.sorted { $0.workout.start < $1.workout.start }
    }

    var body: some View {
        VStack(spacing: 16) {
            ActivitySummaryCard(day: day)

            SectionHeader(title: "Timeline", subtitle: "Sleep and workouts across the day")
            DayTimeline(day: day)
                .card()

            let count = workouts.count + (day.sleep == nil ? 0 : 1) + (day.sleep?.naps.count ?? 0)
            SectionHeader(title: "Completed activities", subtitle: count == 1 ? "1 activity" : "\(count) activities")
            VStack(spacing: 12) {
                if let sleep = day.sleep {
                    NavigationLink(value: TodayRoute.sleep(day.date)) {
                        SleepActivityCard(sleep: sleep)
                    }
                }
                ForEach(workouts) { workout in
                    NavigationLink(value: TodayRoute.strain(day.date)) {
                        WorkoutActivityCard(workout: workout, dayStrain: day.strain.score)
                    }
                }
                if workouts.isEmpty {
                    EmptyStateView(symbol: "figure.walk.motion", title: "No workouts",
                                   message: "Workouts recorded on your Apple Watch will show up here with their strain and heart-rate zones.")
                }
            }
            .buttonStyle(.plain)

            SectionHeader(title: "Last 7 days")
            WeekActivityCard(days: model.history(endingAt: day, count: 7), selected: day.date)
        }
    }
}

// MARK: - Summary

private struct ActivitySummaryCard: View {
    let day: DayMetrics

    private var activeTime: TimeInterval {
        day.strain.workouts.reduce(0) { $0 + $1.workout.duration }
    }

    private var workoutCalories: Double {
        day.strain.workouts.compactMap(\.workout.activeEnergy).reduce(0, +)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                ScoreRing.strain(day, size: 118, lineWidth: 11, showTarget: true)
                    .padding(6)
                VStack(alignment: .leading, spacing: 6) {
                    Text("DAY STRAIN")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(Theme.secondaryText)
                    Text(StrainDetailView.level(for: day.strain.score).uppercased())
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Theme.strain)
                    if let target = day.strainTarget {
                        targetStatus(target)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider().overlay(Theme.stroke)

            Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    StatCell(title: "Workouts", value: "\(day.strain.workouts.count)")
                    StatCell(title: "Active time", value: activeTime > 0 ? Format.duration(activeTime) : "–")
                }
                GridRow {
                    StatCell(title: "Calories", value: day.activeEnergy.map(Format.thousands) ?? "–",
                             detail: workoutCalories > 0 ? "\(Format.thousands(workoutCalories)) from workouts" : "active kcal")
                    StatCell(title: "Steps", value: day.steps.map(Format.thousands) ?? "–",
                             detail: day.strain.averageHR.map { "Avg HR \(Format.whole($0)) bpm" })
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func targetStatus(_ target: ClosedRange<Double>) -> some View {
        let score = day.strain.score
        let (text, symbol, color): (String, String, Color) =
            if score < target.lowerBound {
                ("\(Format.strain(target.lowerBound - score)) to reach target", "arrow.up.right", Theme.secondaryText)
            } else if score <= target.upperBound {
                ("On target", "checkmark.circle.fill", Theme.green)
            } else {
                ("Above target", "exclamationmark.triangle.fill", Theme.yellow)
            }
        VStack(alignment: .leading, spacing: 2) {
            Label(text, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text("Target \(Format.strainRange(target))")
                .font(.caption2)
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

// MARK: - Timeline

private struct DayTimeline: View {
    let day: DayMetrics

    private struct Block: Identifiable {
        let id = UUID()
        let start: Date
        let end: Date
        let color: Color
    }

    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: day.date)! }

    private var domainStart: Date { min(day.sleep?.start ?? day.date, day.date) }

    private var blocks: [Block] {
        var blocks: [Block] = []
        if let sleep = day.sleep {
            blocks.append(Block(start: sleep.start, end: sleep.end, color: Theme.sleep))
            blocks += sleep.naps.map { Block(start: $0.start, end: $0.end, color: Theme.sleep.opacity(0.7)) }
        }
        blocks += day.strain.workouts.map { Block(start: $0.workout.start, end: $0.workout.end, color: Theme.strain) }
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Chart {
                RectangleMark(xStart: .value("Start", domainStart), xEnd: .value("End", dayEnd), y: .value("Row", "Day"), height: .ratio(0.7))
                    .foregroundStyle(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                ForEach(blocks) { block in
                    RectangleMark(xStart: .value("Start", block.start), xEnd: .value("End", max(block.end, block.start.addingTimeInterval(10 * 60))),
                                  y: .value("Row", "Day"), height: .ratio(0.7))
                        .foregroundStyle(block.color.gradient)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if Calendar.current.isDateInToday(day.date) {
                    RuleMark(x: .value("Now", Date.now))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXScale(domain: domainStart...dayEnd)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 6)) {
                    AxisGridLine().foregroundStyle(Theme.stroke)
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 64)

            HStack(spacing: 16) {
                legend(color: Theme.sleep, title: "Sleep")
                legend(color: Theme.strain, title: "Workout")
                Spacer()
            }
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.secondaryText)
        }
    }
}

// MARK: - Activity cards

private struct ActivityCardHeader: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).font(.score(28))
                Text(caption.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.tertiaryText)
        }
    }
}

private struct SleepActivityCard: View {
    let sleep: SleepSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ActivityCardHeader(symbol: "moon.fill", color: Theme.sleep, title: "Sleep",
                               subtitle: Format.timeRange(sleep.start, sleep.end),
                               value: Format.percent(sleep.performance), caption: "performance")
            HStack {
                StatCell(title: "Asleep", value: Format.duration(sleep.asleep))
                StatCell(title: "Need", value: Format.duration(sleep.need.total))
                StatCell(title: "Restorative", value: sleep.hasStages ? Format.duration(sleep.restorative) : "–")
                StatCell(title: "Naps", value: sleep.naps.isEmpty ? "–" : Format.duration(sleep.napTime))
            }
        }
        .card()
    }
}

private struct WorkoutActivityCard: View {
    let workout: WorkoutStrain
    let dayStrain: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ActivityCardHeader(symbol: workout.workout.symbol, color: Theme.strain, title: workout.workout.name,
                               subtitle: Format.timeRange(workout.workout.start, workout.workout.end),
                               value: Format.strain(workout.strain), caption: "strain")
            HStack {
                StatCell(title: "Duration", value: Format.duration(workout.workout.duration))
                StatCell(title: "Avg HR", value: workout.averageHR.map(Format.whole) ?? "–")
                StatCell(title: "Max HR", value: workout.maxHR.map(Format.whole) ?? "–")
                if let distance = workout.workout.distance {
                    StatCell(title: "Distance", value: Format.distance(distance))
                } else {
                    StatCell(title: "Calories", value: workout.workout.activeEnergy.map(Format.thousands) ?? "–")
                }
            }
            ZoneStrip(minutes: workout.zoneMinutes)
        }
        .card()
    }
}

/// A stacked bar of time in each heart-rate zone, with per-zone minutes underneath.
private struct ZoneStrip: View {
    let minutes: [Double]

    var body: some View {
        let total = minutes.reduce(0, +)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    if total > 0 {
                        let zones = minutes.indices.filter { minutes[$0] > 0 }
                        let gaps = CGFloat(zones.count - 1) * 2
                        ForEach(zones, id: \.self) { zone in
                            Rectangle()
                                .fill(Theme.zoneColors[zone])
                                .frame(width: max(2, (proxy.size.width - gaps) * minutes[zone] / total))
                        }
                    } else {
                        Rectangle().fill(Color.white.opacity(0.08))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                ForEach(minutes.indices, id: \.self) { zone in
                    HStack(spacing: 4) {
                        Circle().fill(Theme.zoneColors[zone]).frame(width: 6, height: 6)
                        Text("Z\(zone + 1)")
                            .foregroundStyle(Theme.tertiaryText)
                        Text(Format.duration(minutes[zone] * 60))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - Week

private struct WeekActivityCard: View {
    let days: [DayMetrics]
    let selected: Date

    private func activeMinutes(_ day: DayMetrics) -> Double {
        day.strain.workouts.reduce(0) { $0 + $1.workout.duration } / 60
    }

    var body: some View {
        let workouts = days.flatMap(\.strain.workouts)
        let totalTime = workouts.reduce(0) { $0 + $1.workout.duration }
        let calories = days.compactMap(\.activeEnergy).reduce(0, +)
        let ceiling = max(days.map(activeMinutes).max() ?? 0, 30) * 1.25

        VStack(spacing: 18) {
            Chart(days) { day in
                let minutes = activeMinutes(day)
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Minutes", minutes), width: .ratio(0.55))
                    .foregroundStyle(Theme.strain.opacity(day.date == selected ? 1 : 0.45).gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .annotation(position: .top) {
                        if minutes > 0 {
                            Text(Format.duration(minutes * 60))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(day.date == selected ? .white : Theme.secondaryText)
                        }
                    }
            }
            .chartYScale(domain: 0...ceiling)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .frame(height: 140)

            Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                GridRow {
                    StatCell(title: "Workouts", value: "\(workouts.count)")
                    StatCell(title: "Active time", value: totalTime > 0 ? Format.duration(totalTime) : "–")
                }
                GridRow {
                    StatCell(title: "Avg strain", value: days.map(\.strain.score).mean.map(Format.strain) ?? "–")
                    StatCell(title: "Active kcal", value: calories > 0 ? Format.thousands(calories) : "–")
                }
            }
        }
        .card()
    }
}
