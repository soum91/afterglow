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
                if store.token != nil { Task { await store.syncDevices() } }
                else { Task { await BridgeSync.pushIfChanged() } }
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
        // afterglow://sync (from Keystone): pick up new devices and send them to the bridge now.
        .onOpenURL { url in
            if url.host == "sync" { Task { await store.syncDevices(force: true) } }
        }
        .alert(store.newSwitches.first.map { "New in Smart Life: \($0.name)" } ?? "",
               isPresented: Binding(get: { !store.newSwitches.isEmpty }, set: { _ in })) {
            Button("It's a light, add it") {
                if let d = store.newSwitches.first {
                    store.newSwitches.removeFirst()
                    Task { await store.include(d.id, true) }
                }
            }
            Button("Not a light", role: .cancel) {
                if !store.newSwitches.isEmpty { store.newSwitches.removeFirst() }
            }
        } message: {
            Text("Is there a light on this switch or plug? Add it and it shows up in Afterglow, Keystone and Apple Home.")
        }
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
        AppShortcut(intent: TurnLightOnIntent(), phrases: [
            "Turn on \(\.$light) in \(.applicationName)",
            "\(.applicationName) \(\.$light) on",
            "Switch on \(\.$light) with \(.applicationName)",
        ], shortTitle: "Turn Light On", systemImageName: "lightbulb.max")
        AppShortcut(intent: TurnLightOffIntent(), phrases: [
            "Turn off \(\.$light) in \(.applicationName)",
            "\(.applicationName) \(\.$light) off",
            "Switch off \(\.$light) with \(.applicationName)",
        ], shortTitle: "Turn Light Off", systemImageName: "lightbulb")
        AppShortcut(intent: RunSceneIntent(), phrases: [
            "Run \(\.$scene) in \(.applicationName)",
            "Set \(.applicationName) to \(\.$scene)",
            "\(.applicationName) \(\.$scene)",
        ], shortTitle: "Run Scene", systemImageName: "sparkles")
        AppShortcut(intent: ToggleLightIntent(), phrases: [
            "Toggle \(\.$light) in \(.applicationName)",
            "Switch \(\.$light) with \(.applicationName)",
        ], shortTitle: "Toggle Light", systemImageName: "lightswitch.on")
        AppShortcut(intent: ToggleAllLightsShortcutIntent(), phrases: [
            "Switch all lights with \(.applicationName)",
            "Toggle all lights in \(.applicationName)",
            "\(.applicationName) light switch",
        ], shortTitle: "Light Switch", systemImageName: "lightbulb.fill")
        AppShortcut(intent: LightsOffIfTVOffIntent(), phrases: [
            "Bedtime in \(.applicationName)",
        ], shortTitle: "Lights Off If TV Off", systemImageName: "tv.slash")
    }
}


/// App-only shortcut for Apple's built-in Control Center Shortcut control.
/// Keeping this out of the widget extension prevents duplicate App Intents
/// from being resolved to the extension instead of the app's process.
struct ToggleAllLightsShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle All Lights"
    static var description = IntentDescription("Switch all Afterglow lights on or off with one tap.")

    func perform() async throws -> some IntentResult {
        _ = try await Lights.toggle(nil)
        return .result()
    }
}
