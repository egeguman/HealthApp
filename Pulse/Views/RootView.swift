import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

enum AppTab: Hashable {
    case today, trends, settings
}

struct MainTabView: View {
    @State private var tab = LaunchOptions.initialTab

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "circle.circle", value: AppTab.today) {
                TodayView()
            }
            Tab("Trends", systemImage: "chart.bar.xaxis", value: AppTab.trends) {
                TrendsView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
        }
        .tint(.white)
    }
}

/// Launch arguments for jumping straight to a screen in the simulator, e.g. `--open sleep --anchor bottom`.
enum LaunchOptions {
    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static var openArgument: String? { argument(after: "--open") }

    static var scrollAnchor: UnitPoint? {
        switch argument(after: "--anchor") {
        case "center": .center
        case "bottom": .bottom
        default: nil
        }
    }

    static var initialTab: AppTab {
        switch openArgument {
        case "trends": .trends
        case "settings": .settings
        default: .today
        }
    }

    static var initialRoute: TodayRoute? {
        let today = Calendar.current.startOfDay(for: .now)
        return switch openArgument {
        case "recovery": .recovery(today)
        case "strain": .strain(today)
        case "sleep": .sleep(today)
        default: nil
        }
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var isConnecting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ZStack {
                    ScoreRing(progress: 0.72, color: Theme.sleep, value: "", size: 150, lineWidth: 10)
                    ScoreRing(progress: 0.86, color: Theme.green, value: "", size: 112, lineWidth: 10)
                    ScoreRing(progress: 0.55, color: Theme.strain, value: "", size: 74, lineWidth: 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Know when to push.\nKnow when to rest.")
                        .font(.system(size: 34, weight: .bold).width(.condensed))
                    Text("Pulse turns the data your Apple Watch already collects into three simple daily scores, and tells you what they mean.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                }

                VStack(alignment: .leading, spacing: 18) {
                    feature(symbol: "bolt.heart.fill", color: Theme.green, title: "Recovery",
                            text: "How ready your body is, from overnight HRV, resting heart rate and sleep.")
                    feature(symbol: "flame.fill", color: Theme.strain, title: "Strain",
                            text: "How hard your heart worked today on a 0–21 scale, with a daily target.")
                    feature(symbol: "moon.stars.fill", color: Theme.sleep, title: "Sleep",
                            text: "How much of the sleep you actually needed you got, and when to go to bed tonight.")
                }

                VStack(spacing: 12) {
                    Button {
                        isConnecting = true
                        Task {
                            await model.connectAppleHealth()
                            isConnecting = false
                        }
                    } label: {
                        HStack {
                            if isConnecting { ProgressView().tint(.black) }
                            Image(systemName: "heart.fill")
                            Text("Connect Apple Health")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .disabled(isConnecting)

                    Button("Explore with demo data") {
                        Task { await model.startDemo() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 6)

                    Label("Read-only. Your data stays on your iPhone.", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.tertiaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .screenBackground()
    }

    private func feature(symbol: String, color: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
