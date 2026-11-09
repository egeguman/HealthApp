import SwiftUI

/// A compact tile: what the metric is, today's value, and how it compares to normal.
struct MetricTile: View {
    let title: String
    let symbol: String
    let value: String
    var unit: String = ""
    var comparison: Comparison?

    struct Comparison {
        let text: String
        let isGood: Bool?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.score(28))
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tertiaryText)
            }
            if let comparison {
                Text(comparison.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(comparison.isGood.map { $0 ? Theme.green : Theme.yellow } ?? Theme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .card(padding: 14)
    }
}

extension MetricTile.Comparison {
    /// Compares a value to its baseline. `higherIsBetter` decides the color; `nil` keeps it neutral.
    static func versus(_ value: Double?, _ baseline: Baseline?, higherIsBetter: Bool?, threshold: Double, format: (Double) -> String) -> Self? {
        guard let value, let baseline else { return nil }
        let diff = value - baseline.mean
        guard abs(diff) >= threshold else {
            return .init(text: "Normal · avg \(format(baseline.mean))", isGood: nil)
        }
        let arrow = diff > 0 ? "▲" : "▼"
        let isGood = higherIsBetter.map { $0 == (diff > 0) }
        return .init(text: "\(arrow) \(format(abs(diff))) vs avg \(format(baseline.mean))", isGood: isGood)
    }
}

/// Shows where today's value sits relative to the user's typical range.
struct RangeBar: View {
    let value: Double
    let baseline: Baseline
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let spread = max(baseline.standardDeviation, baseline.mean * 0.02)
            let lower = baseline.mean - spread * 3
            let upper = baseline.mean + spread * 3
            let position = { (v: Double) in CGFloat(((v - lower) / (upper - lower)).clamped(to: 0...1)) * proxy.size.width }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: position(baseline.mean + spread) - position(baseline.mean - spread))
                    .offset(x: position(baseline.mean - spread))
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .offset(x: position(value) - 6)
            }
        }
        .frame(height: 12)
    }
}

struct InsightCard: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: insight.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.color(for: insight.tone))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(insight.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

/// The large "what to do today" card, tinted by recovery.
struct HeadlineCard: View {
    let insight: Insight

    var body: some View {
        let color = Theme.color(for: insight.tone)
        VStack(alignment: .leading, spacing: 8) {
            Label(insight.title, systemImage: insight.symbol)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text(insight.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [color.opacity(0.22), color.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(color.opacity(0.3)))
    }
}

/// A label/value pair for stat grids.
struct StatCell: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.score(22))
                .foregroundStyle(.white)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .card()
    }
}
