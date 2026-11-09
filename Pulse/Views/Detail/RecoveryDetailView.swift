import SwiftUI

struct RecoveryDetailView: View {
    @Environment(AppModel.self) private var model
    let date: Date

    var body: some View {
        ScrollView {
            if let day = model.days.first(where: { $0.date == date }) {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        ScoreRing.recovery(day, size: 190, lineWidth: 16)
                        Text(day.recovery?.zone.title.uppercased() ?? "NOT AVAILABLE")
                            .font(.subheadline.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(day.recovery.map { Theme.color(for: $0.zone) } ?? Theme.secondaryText)
                    }
                    .padding(.vertical, 12)

                    HeadlineCard(insight: InsightEngine.headline(for: day))

                    if let recovery = day.recovery {
                        SectionHeader(title: "What's driving it", subtitle: "Last night compared with your previous 30 days")
                        ForEach(recovery.contributors) { contributor in
                            ContributorCard(contributor: contributor)
                        }
                    }

                    SectionHeader(title: "Last 7 days")
                    RecoveryHistoryChart(days: model.history(endingAt: day, count: 7))
                        .card()

                    ExplainerCard(title: "How Recovery works", text: """
                        Each morning Pulse compares last night's heart rate variability, resting heart rate, sleep and breathing rate \
                        with your own 30-day normal. HRV carries the most weight because it's the clearest signal of how relaxed \
                        your nervous system is. Green (67–100%) means you're ready for strain, yellow (34–66%) means maintain, \
                        and red (0–33%) means your body needs rest.
                        """)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .defaultScrollAnchor(LaunchOptions.scrollAnchor)
        .screenBackground()
        .navigationTitle("Recovery")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ContributorCard: View {
    let contributor: RecoveryContributor

    private var info: (name: String, symbol: String, unit: String, explanation: String) {
        switch contributor.kind {
        case .hrv:
            ("Heart Rate Variability", "waveform.path.ecg", "ms",
             "The variation in time between heartbeats. Higher than your normal means your body is recovered.")
        case .restingHR:
            ("Resting Heart Rate", "heart.fill", "bpm",
             "Your lowest heart rate while asleep. Above normal can signal stress, illness, alcohol or a late meal.")
        case .sleep:
            ("Sleep Performance", "moon.stars.fill", "%",
             "How much of last night's sleep need you got. Below 85% starts to hold recovery back.")
        case .respiratoryRate:
            ("Respiratory Rate", "lungs.fill", "rpm",
             "Breaths per minute while asleep. It's usually very stable, so a jump can be an early sign of illness.")
        }
    }

    private var impact: (text: String, color: Color) {
        switch contributor.effect {
        case 0.5...: ("Boosting", Theme.green)
        case ...(-0.5): ("Lowering", Theme.red)
        default: ("Normal", Theme.secondaryText)
        }
    }

    private func format(_ value: Double) -> String {
        contributor.kind == .respiratoryRate ? Format.oneDecimal(value) : Format.whole(value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(info.name, systemImage: info.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(impact.text.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(impact.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(impact.color.opacity(0.15), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(format(contributor.value)).font(.score(34))
                Text(info.unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
                Spacer()
                if let baseline = contributor.baseline {
                    Text("Usual \(format(baseline.mean)) \(info.unit)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            if let baseline = contributor.baseline {
                VStack(spacing: 6) {
                    RangeBar(value: contributor.value, baseline: baseline, color: impact.color == Theme.secondaryText ? .white : impact.color)
                    HStack {
                        Text("Lower")
                        Spacer()
                        Text("Your normal range")
                        Spacer()
                        Text("Higher")
                    }
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
                }
            } else {
                ProgressView(value: min(contributor.value / 100, 1))
                    .tint(Theme.sleep)
            }
            Text(info.explanation)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}

struct ExplainerCard: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "info.circle")
                .font(.subheadline.weight(.semibold))
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
