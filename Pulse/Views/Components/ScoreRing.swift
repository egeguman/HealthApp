import SwiftUI

/// A circular gauge with the value in the middle. Optionally marks a target band around the ring.
struct ScoreRing: View {
    var progress: Double
    var color: Color
    var value: String
    var unit: String?
    var caption: String?
    var target: ClosedRange<Double>?
    var size: CGFloat = 100
    var lineWidth: CGFloat = 9

    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: lineWidth * 0.8)
            if let target {
                Circle()
                    .trim(from: target.lowerBound, to: target.upperBound)
                    .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: max(lineWidth * 0.28, 2), lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-lineWidth * 0.95)
            }
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value)
                        .font(.score(size * 0.3))
                        .contentTransition(.numericText())
                    if let unit {
                        Text(unit)
                            .font(.system(size: size * 0.13, weight: .bold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                if let caption {
                    Text(caption)
                        .font(.system(size: max(size * 0.085, 10), weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(.uppercase)
                }
            }
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { shown = progress.clamped(to: 0...1) }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 0.6)) { shown = newValue.clamped(to: 0...1) }
        }
    }
}

/// The ring plus its label, as used in the three-up summary on the Today screen.
struct LabeledScoreRing: View {
    let title: String
    let ring: ScoreRing

    var body: some View {
        VStack(spacing: 10) {
            ring
            HStack(spacing: 3) {
                Text(title.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

extension ScoreRing {
    static func recovery(_ day: DayMetrics?, size: CGFloat = 100, lineWidth: CGFloat = 9) -> ScoreRing {
        guard let recovery = day?.recovery else {
            return ScoreRing(progress: 0, color: Theme.neutral, value: "–", size: size, lineWidth: lineWidth)
        }
        return ScoreRing(progress: Double(recovery.score) / 100, color: Theme.color(for: recovery.zone),
                         value: "\(recovery.score)", unit: "%", size: size, lineWidth: lineWidth)
    }

    static func strain(_ day: DayMetrics?, size: CGFloat = 100, lineWidth: CGFloat = 9, showTarget: Bool = false) -> ScoreRing {
        let score = day?.strain.score ?? 0
        let target = showTarget ? day?.strainTarget.map { ($0.lowerBound / StrainSummary.maximum)...($0.upperBound / StrainSummary.maximum) } : nil
        return ScoreRing(progress: score / StrainSummary.maximum, color: Theme.strain, value: Format.strain(score),
                         target: target, size: size, lineWidth: lineWidth)
    }

    static func sleep(_ day: DayMetrics?, size: CGFloat = 100, lineWidth: CGFloat = 9) -> ScoreRing {
        guard let sleep = day?.sleep else {
            return ScoreRing(progress: 0, color: Theme.sleep, value: "–", size: size, lineWidth: lineWidth)
        }
        return ScoreRing(progress: sleep.score, color: Theme.sleep, value: "\(Int((sleep.score * 100).rounded()))",
                         unit: "%", size: size, lineWidth: lineWidth)
    }
}
