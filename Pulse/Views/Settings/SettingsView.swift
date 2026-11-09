import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("Data source", selection: Binding(
                        get: { model.settings.useDemoData },
                        set: { useDemo in
                            Task {
                                if useDemo { await model.startDemo() } else { await model.connectAppleHealth() }
                            }
                        }
                    )) {
                        Text("Apple Health").tag(false)
                        Text("Demo data").tag(true)
                    }
                    if !model.settings.useDemoData {
                        Button("Review Health permissions") {
                            Task { await model.connectAppleHealth() }
                        }
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Pulse only reads from Health and never writes to it. To change access later, open the Health app, tap your profile, then Apps → Pulse.")
                }

                Section {
                    Stepper(value: $model.settings.sleepNeedHours, in: 6...10, step: 0.25) {
                        LabeledContent("Baseline sleep need", value: Format.duration(model.settings.sleepNeedHours * 3600))
                    }
                    Toggle("Custom max heart rate", isOn: Binding(
                        get: { model.settings.maxHeartRateOverride != nil },
                        set: { model.settings.maxHeartRateOverride = $0 ? Int(model.maxHeartRate.rounded()) : nil }
                    ))
                    if model.settings.maxHeartRateOverride != nil {
                        Stepper(value: Binding(
                            get: { model.settings.maxHeartRateOverride ?? 190 },
                            set: { model.settings.maxHeartRateOverride = $0 }
                        ), in: 150...220) {
                            LabeledContent("Max heart rate", value: "\(model.settings.maxHeartRateOverride ?? 190) bpm")
                        }
                    } else {
                        LabeledContent("Max heart rate", value: "\(Format.whole(model.maxHeartRate)) bpm")
                    }
                } header: {
                    Text("Personalize")
                } footer: {
                    Text("Max heart rate: \(model.maxHeartRateSource.description.lowercased()). It sets your heart rate zones and how strain is calculated.")
                }

                Section("Learn") {
                    NavigationLink("How the scores work") { ScoreGuideView() }
                }

                Section {
                    LabeledContent("Last updated", value: model.lastUpdated?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("Settings")
        }
    }
}

struct ScoreGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guide(symbol: "bolt.heart.fill", color: Theme.green, title: "Recovery · 0–100%", text: """
                    How prepared your body is to take on strain, calculated each morning. It compares last night's heart rate \
                    variability (50% weight), resting heart rate (20%), sleep performance (20%) and respiratory rate (10%) \
                    with your own 30-day baseline. Everyone's numbers are different, so only your trend matters.

                    Green (67–100%): primed for a hard day.
                    Yellow (34–66%): maintain with moderate effort.
                    Red (0–33%): your body is stressed, so rest and recover.
                    """)
                guide(symbol: "flame.fill", color: Theme.strain, title: "Strain · 0–21", text: """
                    How much load your heart took on today, from workouts and everything else. It uses time above 50% of your \
                    max heart rate, weighting harder efforts exponentially (Banister TRIMP), then maps it onto a logarithmic \
                    0–21 scale.

                    0–9 Light · 10–13 Moderate · 14–17 High · 18–21 All out.
                    Your optimal strain target rises with your recovery.
                    """)
                guide(symbol: "moon.stars.fill", color: Theme.sleep, title: "Sleep · 0–100%", text: """
                    Sleep performance is the share of your sleep need you actually got. Your need starts at your baseline \
                    (set in Settings), and goes up after high-strain days and when you're carrying sleep debt from recent short nights. \
                    Naps count toward it.
                    """)
                Text("Pulse is a wellness app, not a medical device. Talk to a doctor about any health concerns.")
                    .font(.caption)
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("How scores work")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func guide(symbol: String, color: Color, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
