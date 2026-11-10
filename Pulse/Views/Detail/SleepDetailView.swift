import SwiftUI

struct SleepDetailView: View {
    @Environment(AppModel.self) private var model
    let date: Date

    var body: some View {
        ScrollView {
            if let day = model.days.first(where: { $0.date == date }) {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        ScoreRing.sleep(day, size: 190, lineWidth: 16)
                        Text("SLEEP SCORE")
                            .font(.subheadline.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.sleep)
                        if let sleep = day.sleep {
                            Text("\(Format.duration(sleep.totalAsleep)) of \(Format.duration(sleep.need.total)) needed · \(Format.percent(sleep.performance))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 12)

                    if let sleep = day.sleep {
                        SleepContent(day: day, sleep: sleep, isToday: Calendar.current.isDateInToday(day.date))
                    } else {
                        EmptyStateView(symbol: "moon.zzz", title: "No sleep recorded",
                                       message: "Wear your Apple Watch to bed and set up a Sleep schedule in the Health app to see sleep stages here.")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .defaultScrollAnchor(LaunchOptions.scrollAnchor)
        .screenBackground()
        .navigationTitle("Sleep")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SleepContent: View {
    let day: DayMetrics
    let sleep: SleepSummary
    let isToday: Bool

    var body: some View {
        VStack(spacing: 16) {
            if isToday, let bedtime = day.recommendedBedtime {
                HStack(spacing: 14) {
                    Image(systemName: "bed.double.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.sleep)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tonight, aim for bed by \(Format.time(bedtime))")
                            .font(.headline)
                        Text("You'll need \(Format.duration(day.tonightNeed.total)) of sleep after today's strain.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .card()
            }

            SectionHeader(title: "Sleep stages", subtitle: Format.timeRange(sleep.start, sleep.end))
            VStack(alignment: .leading, spacing: 18) {
                HypnogramChart(sleep: sleep)
                if sleep.hasStages {
                    StageBreakdown(sleep: sleep)
                }
            }
            .card()

            SectionHeader(title: "Sleep quality")
            Grid(horizontalSpacing: 12, verticalSpacing: 18) {
                GridRow {
                    StatCell(title: "Time in bed", value: Format.duration(sleep.timeInBed))
                    StatCell(title: "Efficiency", value: Format.percent(sleep.efficiency), detail: "Asleep vs in bed · 85%+ is great")
                }
                GridRow {
                    StatCell(title: "Restorative", value: Format.duration(sleep.restorative), detail: "Deep + REM sleep")
                    StatCell(title: "Wake-ups", value: "\(sleep.disturbances)", detail: "Times you woke up")
                }
                GridRow {
                    StatCell(title: "Consistency", value: sleep.consistency.map(Format.percent) ?? "–", detail: "Same bed & wake times")
                    StatCell(title: "Respiratory", value: day.respiratoryRate.map { "\(Format.oneDecimal($0)) rpm" } ?? "–", detail: "Breaths per minute")
                }
            }
            .card()

            SectionHeader(title: "Why you needed \(Format.duration(sleep.need.total))")
            VStack(spacing: 10) {
                needRow("Baseline need", sleep.need.baseline, "Set in Settings")
                needRow("Recovering from strain", sleep.need.strain, "Hard days need more sleep")
                needRow("Paying back sleep debt", sleep.need.debt, "About half of each shortfall carries over")
                Divider().overlay(Theme.stroke)
                HStack {
                    Text("Total need").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Format.duration(sleep.need.total)).font(.score(20))
                }
                if sleep.napTime > 0 {
                    HStack {
                        Text("Naps counted").font(.caption).foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Text(Format.duration(sleep.napTime)).font(.caption.weight(.semibold))
                    }
                }
            }
            .card()
        }
    }

    private func needRow(_ title: String, _ value: TimeInterval, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption2).foregroundStyle(Theme.tertiaryText)
            }
            Spacer()
            Text("+\(Format.duration(value))")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(value > 0 ? .white : Theme.tertiaryText)
        }
    }
}

private struct StageBreakdown: View {
    let sleep: SleepSummary

    private let stages: [(stage: SleepStage, typical: String)] = [
        (.awake, "Under 10% is typical"),
        (.rem, "20–25% is typical"),
        (.core, "45–55% is typical"),
        (.deep, "13–23% is typical"),
    ]

    var body: some View {
        let total = max(sleep.timeInBed, 1)
        VStack(spacing: 12) {
            ForEach(stages, id: \.stage) { item in
                let duration = sleep.duration(of: item.stage) + (item.stage == .core ? sleep.duration(of: .unspecified) : 0)
                HStack(spacing: 12) {
                    Circle()
                        .fill(Theme.color(for: item.stage))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.stage.title).font(.subheadline.weight(.semibold))
                        Text(item.typical).font(.caption2).foregroundStyle(Theme.tertiaryText)
                    }
                    Spacer()
                    Text(Format.duration(duration))
                        .font(.subheadline.monospacedDigit())
                    Text(Format.percent(duration / total))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }
}
