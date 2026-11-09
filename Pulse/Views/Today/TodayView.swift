import SwiftUI

enum TodayRoute: Hashable {
    case recovery(Date)
    case strain(Date)
    case sleep(Date)
}

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [TodayRoute] = LaunchOptions.initialRoute.map { [$0] } ?? []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    DayHeader()
                    if let day = model.selectedDay {
                        DayContent(day: day, isToday: model.isViewingToday)
                    } else if model.isLoading {
                        ProgressView()
                            .padding(.top, 160)
                    } else {
                        EmptyStateView(symbol: "heart.text.square", title: "No data yet",
                                       message: "Pull down to refresh once your Apple Watch has synced with Health.")
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

private struct DayHeader: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            Button { model.step(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.canGoBack)

            Spacer()
            VStack(spacing: 2) {
                Text(Format.dayTitle(model.selectedDate).uppercased())
                    .font(.headline.weight(.heavy))
                    .tracking(1.6)
                Text(model.isViewingToday
                     ? model.selectedDate.formatted(.dateTime.weekday(.wide).month().day())
                     : (model.isLoading ? "Updating…" : " "))
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            Spacer()

            Button { model.step(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.canGoForward)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.top, 4)
    }
}

private struct DayContent: View {
    @Environment(AppModel.self) private var model
    let day: DayMetrics
    let isToday: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 8) {
                NavigationLink(value: TodayRoute.sleep(day.date)) {
                    LabeledScoreRing(title: "Sleep", ring: .sleep(day))
                }
                NavigationLink(value: TodayRoute.recovery(day.date)) {
                    LabeledScoreRing(title: "Recovery", ring: .recovery(day))
                }
                NavigationLink(value: TodayRoute.strain(day.date)) {
                    LabeledScoreRing(title: "Strain", ring: .strain(day))
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)

            HeadlineCard(insight: InsightEngine.headline(for: day))

            let insights = InsightEngine.insights(for: day, isToday: isToday)
            if !insights.isEmpty {
                SectionHeader(title: "What stands out")
                ForEach(insights) { insight in
                    InsightCard(insight: insight)
                }
            }

            SectionHeader(title: "Health monitor", subtitle: "Last night vs your 30-day average")
            HealthMonitorGrid(day: day)

            SectionHeader(title: "Activities")
            ActivitiesList(day: day)
        }
    }
}

private struct HealthMonitorGrid: View {
    let day: DayMetrics

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            MetricTile(title: "HRV", symbol: "waveform.path.ecg", value: day.hrv.map(Format.whole) ?? "–", unit: "ms",
                       comparison: .versus(day.hrv, day.baselines.hrv, higherIsBetter: true, threshold: 3, format: Format.whole))
            MetricTile(title: "Resting HR", symbol: "heart.fill", value: day.restingHR.map(Format.whole) ?? "–", unit: "bpm",
                       comparison: .versus(day.restingHR, day.baselines.restingHR, higherIsBetter: false, threshold: 2, format: Format.whole))
            MetricTile(title: "Respiratory", symbol: "lungs.fill", value: day.respiratoryRate.map(Format.oneDecimal) ?? "–", unit: "rpm",
                       comparison: .versus(day.respiratoryRate, day.baselines.respiratoryRate, higherIsBetter: false, threshold: 0.6, format: Format.oneDecimal))
            MetricTile(title: "Blood Oxygen", symbol: "drop.fill", value: day.oxygenSaturation.map(Format.whole) ?? "–", unit: "%",
                       comparison: .versus(day.oxygenSaturation, day.baselines.oxygenSaturation, higherIsBetter: true, threshold: 1.5, format: Format.whole))
            MetricTile(title: "Wrist Temp", symbol: "thermometer.medium", value: day.wristTemperatureDelta.map(Format.signedTemperature) ?? "–",
                       comparison: day.wristTemperatureDelta.map { abs($0) < 0.5 ? .init(text: "Within normal range", isGood: nil) : .init(text: "Off your baseline", isGood: false) })
            MetricTile(title: "Steps", symbol: "figure.walk", value: day.steps.map(Format.thousands) ?? "–",
                       comparison: day.activeEnergy.map { .init(text: "\(Format.thousands($0)) active kcal", isGood: nil) })
        }
    }
}

private struct ActivitiesList: View {
    let day: DayMetrics

    var body: some View {
        VStack(spacing: 10) {
            if let sleep = day.sleep {
                NavigationLink(value: TodayRoute.sleep(day.date)) {
                    ActivityRow(symbol: "moon.fill", color: Theme.sleep, title: "Sleep",
                                subtitle: Format.timeRange(sleep.start, sleep.end),
                                value: Format.duration(sleep.totalAsleep), caption: "asleep")
                }
            }
            ForEach(day.strain.workouts) { workout in
                NavigationLink(value: TodayRoute.strain(day.date)) {
                    ActivityRow(symbol: workout.workout.symbol, color: Theme.strain, title: workout.workout.name,
                                subtitle: "\(Format.time(workout.workout.start)) · \(Format.duration(workout.workout.duration))",
                                value: Format.strain(workout.strain), caption: "strain")
                }
            }
            if day.sleep == nil && day.strain.workouts.isEmpty {
                Text("No sleep or workouts recorded for this day.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.tertiaryText)
                    .card()
            }
        }
        .buttonStyle(.plain)
    }
}

struct ActivityRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let value: String
    let caption: String

    var body: some View {
        HStack(spacing: 14) {
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
                Text(value).font(.score(24))
                Text(caption.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.tertiaryText)
        }
        .card(padding: 12)
    }
}
