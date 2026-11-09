import SwiftUI

@main
struct PulseApp: App {
    @State private var model = AppModel(settings: PulseApp.launchSettings())
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .task(id: scenePhase) {
                    if scenePhase == .active, model.settings.hasCompletedOnboarding {
                        await model.refresh()
                    }
                }
        }
    }

    /// `--demo` skips onboarding with demo data; `--reset` starts fresh. Handy for the simulator.
    private static func launchSettings() -> AppSettings {
        let arguments = ProcessInfo.processInfo.arguments
        var settings = arguments.contains("--reset") ? AppSettings() : AppSettings.load()
        if arguments.contains("--demo") {
            settings.useDemoData = true
            settings.hasCompletedOnboarding = true
        }
        return settings
    }
}
