import SwiftUI
import UIKit

/// Persisted within Afterglow; a sideload re-sign does not require changing
/// global iOS WidgetKit layout or other apps' extension ownership.
struct HomeDashboardOptions: Codable, Equatable {
    var showBulkActions = true
    var showScenes = true
    var showIntegrations = true
    var showKeystone = true
    var showSurge = true

    static func load() -> Self {
        AppGroup.read(Self.self, "home-dashboard.json") ?? Self()
    }
    func save() { AppGroup.write(self, "home-dashboard.json") }
}

struct HomeCustomizeView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding var options: HomeDashboardOptions

    var body: some View {
        NavigationStack {
            Form {
                Section("Sections") {
                    Toggle("All Lights controls", isOn: $options.showBulkActions)
                    Toggle("Scenes", isOn: $options.showScenes)
                    Toggle("Keystone & Surge panels", isOn: $options.showIntegrations)
                    if options.showIntegrations {
                        Toggle("Keystone status card", isOn: $options.showKeystone)
                        Toggle("Surge strip card", isOn: $options.showSurge)
                    }
                }
                Section {
                    ForEach(store.lights) { l in
                        HStack(spacing: 12) {
                            Image(systemName: l.iconName).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l.name).font(.subheadline.weight(.medium))
                                Text(l.belongsToAllLights ? "Light" : "Other device")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 5)
                            Menu {
                                ForEach(HomeCardSize.allCases, id: \.self) { size in
                                    Button {
                                        store.updateLight(l.id) { $0.cardSize = size }
                                    } label: {
                                        if size == l.resolvedCardSize {
                                            Label(size.name, systemImage: "checkmark")
                                        } else {
                                            Text(size.name)
                                        }
                                    }
                                }
                            } label: {
                                Text(l.resolvedCardSize.name)
                                    .font(.caption)
                            }
                            Button { store.stepLight(l.id, forward: false) } label: {
                                Image(systemName: "arrow.up.circle").font(.title3)
                            }.buttonStyle(.borderless).accessibilityLabel("Move \(l.name) earlier")
                            Button { store.stepLight(l.id, forward: true) } label: {
                                Image(systemName: "arrow.down.circle").font(.title3)
                            }.buttonStyle(.borderless).accessibilityLabel("Move \(l.name) later")
                        }
                        .padding(.vertical, 3)
                    }
                } header: {
                    Text("Cards")
                } footer: {
                    Text("Use arrows or drag cards in Arrange mode on Home. Compact = half width; Wide and Large = full width. Rename, change icons or hide cards under Settings → Lights.")
                }
            }
            .navigationTitle("Customize Home")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: options) { _, value in value.save() }
        }
    }
}

/// These are first-party cards built from Keystone's documented bridge
/// response, not a forbidden attempt to host another app's WidgetKit view.
struct HomeIntegrationCards: View {
    let showKeystone: Bool
    let showSurge: Bool
    @State private var bridge: BridgeInfo?
    @State private var checked = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        if showKeystone || showSurge {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(text: "Connected apps")
                    Spacer()
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(busy)
                    .accessibilityLabel("Refresh Keystone and Surge panels")
                }
                if showKeystone {
                    panel(title: "Keystone", icon: "cpu.fill", accent: .yellow) {
                        if let bridge {
                            Text("Bridge online · build \(bridge.build.map(String.init) ?? "?")")
                                .font(.subheadline)
                            if let room = bridge.govee {
                                if let t = room.temp { Label(String(format: "%.1f °C", t), systemImage: "thermometer") }
                                if let h = room.humidity { Label(String(format: "%.0f%% humidity", h), systemImage: "humidity") }
                            }
                            if let p = bridge.purifier, p.configured == true {
                                Text("Air purifier: \(p.ok == true ? "online" : "not responding")")
                            }
                        } else {
                            Text(statusText).foregroundStyle(.secondary)
                        }
                    } open: { openApp("keystone://") }
                }
                if showSurge {
                    panel(title: "Surge", icon: "poweroutlet.strip.fill", accent: .mint) {
                        if let strip = bridge?.strip {
                            if strip.configured == true {
                                Text("Bridge strip: \(strip.ok == true ? "online" : "not responding")")
                                if let sockets = strip.outlets {
                                    Text("\(sockets.count) mapped socket controls")
                                    ForEach(Array(sockets.prefix(3).enumerated()), id: \.offset) { item in
                                        HStack {
                                            Text(item.element.name)
                                            Spacer()
                                            Text(item.element.on.map { $0 ? "On" : "Off" } ?? "Unknown")
                                        }
                                    }
                                }
                            } else {
                                Text("Individual sockets not configured on Keystone")
                            }
                        } else {
                            Text(bridge == nil ? statusText : "No strip data reported by Keystone")
                                .foregroundStyle(.secondary)
                        }
                        Text("Tuya cloud-only controls remain inside Surge.")
                            .font(.caption).foregroundStyle(.secondary)
                    } open: { openApp("surge://") }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            .task { await refresh() }
        }
    }

    private var statusText: String {
        if !BridgeConfig.stored.isSet {
            return "Connect Keystone in Afterglow's bridge settings for status."
        }
        return checked ? "Keystone bridge unavailable on local Wi-Fi." : "Checking Keystone…"
    }

    private func refresh() async {
        checked = false
        guard BridgeConfig.stored.isSet else {
            bridge = nil
            checked = true
            return
        }
        busy = true
        defer { checked = true; busy = false }
        do { bridge = try await BridgeAPI.info(); message = nil }
        catch {
            bridge = nil
            message = "Bridge status: \(error.localizedDescription)"
        }
    }

    private func panel<Content: View>(title: String, icon: String, accent: Color,
                                      @ViewBuilder content: () -> Content,
                                      open: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(accent)
                Spacer()
                Button("Open") { open() }.font(.subheadline.weight(.medium))
            }
            content()
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func openApp(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok {
                Task { @MainActor in message = "App not installed, or the installed version does not register \(url.scheme ?? "the") links." }
            }
        }
    }
}
