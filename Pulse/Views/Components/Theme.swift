import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.043, blue: 0.055)
    static let card = Color(red: 0.094, green: 0.106, blue: 0.125)
    static let cardRaised = Color(red: 0.133, green: 0.149, blue: 0.173)
    static let stroke = Color.white.opacity(0.07)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.4)

    static let green = Color(red: 0.086, green: 0.902, blue: 0.400)
    static let yellow = Color(red: 1.0, green: 0.800, blue: 0.0)
    static let red = Color(red: 1.0, green: 0.247, blue: 0.318)
    static let strain = Color(red: 0.180, green: 0.580, blue: 1.0)
    static let sleep = Color(red: 0.620, green: 0.640, blue: 1.0)
    static let neutral = Color.white.opacity(0.75)

    static func color(for zone: RecoveryZone) -> Color {
        switch zone {
        case .green: green
        case .yellow: yellow
        case .red: red
        }
    }

    static func color(for tone: Insight.Tone) -> Color {
        switch tone {
        case .positive: green
        case .neutral: strain
        case .caution: yellow
        case .negative: red
        }
    }

    static func color(for stage: SleepStage) -> Color {
        switch stage {
        case .awake: Color(red: 1.0, green: 0.553, blue: 0.443)
        case .rem: Color(red: 0.357, green: 0.800, blue: 1.0)
        case .core, .unspecified: Color(red: 0.302, green: 0.502, blue: 1.0)
        case .deep: Color(red: 0.459, green: 0.302, blue: 0.937)
        case .inBed: Color.white.opacity(0.3)
        }
    }

    static let zoneColors: [Color] = [
        Color(red: 0.55, green: 0.62, blue: 0.70),
        Color(red: 0.20, green: 0.75, blue: 0.95),
        Color(red: 0.15, green: 0.85, blue: 0.45),
        Color(red: 1.00, green: 0.62, blue: 0.10),
        Color(red: 1.00, green: 0.25, blue: 0.32),
    ]

    static let zoneNames = ["Zone 1 · Easy", "Zone 2 · Endurance", "Zone 3 · Tempo", "Zone 4 · Threshold", "Zone 5 · Max"]
}

extension Font {
    /// Condensed, heavy numerals for scores.
    static func score(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold).width(.condensed).monospacedDigit()
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Theme.secondaryText)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}
