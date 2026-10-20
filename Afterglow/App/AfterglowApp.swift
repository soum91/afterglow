import SwiftUI
import BackgroundTasks
import WidgetKit
import AppIntents

@main
struct AfterglowApp: App {
    @StateObject private var store = AppStore.shared
    @Environment(\.scenePhase) private var phase

    init() {
        // Must exist at launch so iOS can deliver arrive/leave events when it relaunches the app in the background.
        _ = Geo.shared
        AfterglowShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .onChange(of: phase, initial: true) { _, newPhase in
            switch newPhase {
            case .active:
                store.startPolling()
                if store.lights.isEmpty, store.token != nil { Task { await store.reloadDevices() } }
                Task { await BridgeSync.pushIfChanged() }
            case .background:
                store.stopPolling()
                Self.scheduleRefresh()
                WidgetCenter.shared.reloadAllTimelines()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppStore.refreshID)) {
            Self.scheduleRefresh()
            await Lights.refresh()
            await MainActor.run { Lights.reloadWidgets() }
        }
    }

    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: AppStore.refreshID)
        req.earliestBeginDate = Date().addingTimeInterval(20 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if store.token == nil {
                LoginView()
            } else {
                HomeView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.token == nil)
        .alert("Something went wrong", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.error ?? "")
        }
    }
}

/// Siri phrases. These work with no setup: "Hey Siri, lights off in Afterglow".
struct AfterglowShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AllLightsOffIntent(), phrases: [
            "Lights off in \(.applicationName)",
            "Turn off the lights in \(.applicationName)",
            "\(.applicationName) lights off",
            "\(.applicationName) goodnight",
        ], shortTitle: "Lights Off", systemImageName: "lightbulb.slash")
        AppShortcut(intent: AllLightsOnIntent(), phrases: [
            "Lights on in \(.applicationName)",
            "Turn on the lights in \(.applicationName)",
            "\(.applicationName) lights on",
        ], shortTitle: "Lights On", systemImageName: "lightbulb.fill")
        AppShortcut(intent: RunSceneIntent(), phrases: [
            "Run \(\.$scene) in \(.applicationName)",
            "Set \(.applicationName) to \(\.$scene)",
            "\(.applicationName) \(\.$scene)",
        ], shortTitle: "Run Scene", systemImageName: "sparkles")
        AppShortcut(intent: ToggleLightIntent(), phrases: [
            "Toggle \(\.$light) in \(.applicationName)",
            "Switch \(\.$light) with \(.applicationName)",
        ], shortTitle: "Toggle Light", systemImageName: "lightswitch.on")
        AppShortcut(intent: LightsOffIfTVOffIntent(), phrases: [
            "Bedtime in \(.applicationName)",
        ], shortTitle: "Lights Off If TV Off", systemImageName: "tv.slash")
    }
}
