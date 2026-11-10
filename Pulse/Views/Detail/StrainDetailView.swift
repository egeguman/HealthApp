import SwiftUI

struct StrainDetailView: View {
    @Environment(AppModel.self) private var model
    let date: Date

    var body: some View {
        ScrollView {
            if let day = model.days.first(where: { $0.date == date }) {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        ScoreRing.strain(day, size: 190, lineWidth: 16, showTarget: true)
                        Text(Self.level(for: day.strain.score).uppercased())
                            .font(.subheadline.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(Theme.strain)
                        if let target = day.strainTarget {
                            Label("Optimal strain for today: \(Format.strainRange(target))", systemImage: "scope")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 12)

                    SectionHeader(title: "Heart rate", subtitle: "Shaded areas are workouts")
                    HeartRateChart(day: day, maxHeartRate: model.maxHeartRate)
                        .card()

                    SectionHeader(title: "Time in heart rate zones", subtitle: "Higher zones build strain much faster")
                    ZoneBreakdown(minutes: day.strain.zoneMinutes, maxHeartRate: model.maxHeartRate)
                        .card()

                    if !day.strain.workouts.isEmpty {
                        SectionHeader(title: "Workouts")
                        ForEach(day.strain.workouts) { workout in
                            WorkoutCard(workout: workout)
                        }
                    }

                    SectionHeader(title: "Day totals")
                    Grid(horizontalSpacing: 12, verticalSpacing: 16) {
                        GridRow {
                            StatCell(title: "Steps", value: day.steps.map(Format.thousands) ?? "–")
                            StatCell(title: "Active energy", value: day.activeEnergy.map { "\(Format.thousands($0)) kcal" } ?? "–")
                        }
                        GridRow {
                            StatCell(title: "Average HR", value: day.strain.averageHR.map { "\(Format.whole($0)) bpm" } ?? "–")
                            StatCell(title: "Peak HR", value: day.strain.peakHR.map { "\(Format.whole($0)) bpm" } ?? "–")
                        }
                    }
                    .card()

                    SectionHeader(title: "Last 7 days")
                    StrainHistoryChart(days: model.history(endingAt: day, count: 7))
                        .card()

                    ExplainerCard(title: "How Strain works", text: """
                        Strain measures how hard your heart worked, from 0 to 21. Only time above 50% of your max heart rate \
                        (\(Format.whole(model.maxHeartRate)) bpm) counts, and harder minutes count exponentially more. The scale is \
                        logarithmic: going from 10 to 11 is easy, going from 18 to 19 takes a huge effort. Each minute in zone 1 \
                        adds 1 point of load and each minute in zone 5 adds 5. The white arc on the ring \
                        is today's optimal range, based on your recovery.
                        """)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .defaultScrollAnchor(LaunchOptions.scrollAnchor)
        .screenBackground()
        .navigationTitle("Strain")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func level(for strain: Double) -> String {
        switch strain {
        case ..<10: "Light"
        case ..<14: "Moderate"
        case ..<18: "High"
        default: "All out"
        }
    }
}

private struct WorkoutCard: View {
    let workout: WorkoutStrain

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: workout.workout.symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.strain)
                    .frame(width: 40, height: 40)
                    .background(Theme.strain.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.workout.name).font(.headline)
                    Text(Format.timeRange(workout.workout.start, workout.workout.end))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.strain(workout.strain)).font(.score(26))
                    Text("STRAIN")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.tertiaryText)
                }
            }
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
        }
        .card()
    }
}
