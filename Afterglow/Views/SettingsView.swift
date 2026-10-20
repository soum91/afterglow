import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { LightsManageView() } label: {
                        LabeledContent("Lights", value: "\(store.visible.count) shown")
                    }
                    Button {
                        Task { await store.findOnWiFi() }
                    } label: {
                        HStack {
                            Label("Find lights on Wi-Fi", systemImage: "wifi")
                            Spacer()
                            if let f = store.finding { Text(f).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                    .disabled(store.finding != nil)
                    Button {
                        Task { await store.reloadDevices() }
                    } label: {
                        Label(store.loading ? "Refreshing…" : "Refresh from Smart Life", systemImage: "arrow.clockwise")
                    }
                } footer: {
                    let local = store.lights.filter(\.hasLocal).count
                    Text("\(local) of \(store.lights.count) reachable on Wi-Fi. Those switch instantly and keep working with the internet down; the rest go through Tuya's cloud.")
                }

                Section("Apple Home & TV") {
                    NavigationLink { HomeBridgeView() } label: {
                        Label("Apple Home bridge", systemImage: "homekit")
                    }
                    NavigationLink { AutomationsView() } label: {
                        Label("TV & automations", systemImage: "tv")
                    }
                }

                Section("Siri, widgets and Control Center") {
                    NavigationLink { ShortcutsGuideView() } label: {
                        Label("Siri & Shortcuts", systemImage: "waveform")
                    }
                    NavigationLink { WidgetsGuideView() } label: {
                        Label("Widgets & Control Center", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Button("Sign out of Smart Life", role: .destructive) {
                        store.signOut()
                        dismiss()
                    }
                } footer: {
                    Text("Afterglow \(AppGroup.version) · shared storage \(AppGroup.isShared ? "on" : "off (widgets can't see your lights)")")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct LightsManageView: View {
    @EnvironmentObject var store: AppStore
    @State private var list: [Light] = []

    var body: some View {
        List {
            Section {
                ForEach($list) { $l in
                    NavigationLink {
                        LightSettingsView(lightID: l.id)
                    } label: {
                        HStack {
                            Image(systemName: l.hidden ? "eye.slash" : "lightbulb.fill")
                                .foregroundStyle(l.hidden ? Color.secondary : l.tint)
                            VStack(alignment: .leading) {
                                Text(l.name)
                                Text(l.hasLocal ? "Wi-Fi \(l.host ?? "")" : "Cloud").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onMove { from, to in
                    list.move(fromOffsets: from, toOffset: to)
                    store.saveLights(list)
                }
            } footer: {
                Text("Drag to reorder. The order is used on the home screen and in widgets. Names come from Smart Life; rename there.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Lights")
        .onAppear { list = store.lights }
        .onChange(of: store.lights) { _, new in list = new }
    }
}

struct LightSettingsView: View {
    @EnvironmentObject var store: AppStore
    let lightID: String
    @State private var host = ""
    @State private var version = 0.0
    @State private var testing: String?

    private var light: Light? { store.lights.first { $0.id == lightID } }

    var body: some View {
        Form {
            if let l = light {
                Section {
                    Toggle("Show in Afterglow", isOn: Binding(get: { !l.hidden }, set: { v in store.updateLight(l.id) { $0.hidden = !v } }))
                } footer: {
                    Text("Hidden lights stay out of the grid, widgets, \"all lights\" and the Apple Home bridge.")
                }
                Section {
                    TextField("IP address (e.g. 192.168.1.42)", text: $host)
                        .keyboardType(.decimalPad)
                    Picker("Protocol", selection: $version) {
                        Text("Auto").tag(0.0)
                        Text("3.3").tag(3.3)
                        Text("3.4").tag(3.4)
                        Text("3.5").tag(3.5)
                    }
                    Button("Save and test") {
                        let h = host.trimmingCharacters(in: .whitespaces)
                        store.updateLight(l.id) { $0.host = h.isEmpty ? nil : h; $0.version = version == 0 ? nil : version }
                        Task { await test() }
                    }
                    if let testing { Text(testing).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Wi-Fi")
                } footer: {
                    Text("Usually found automatically. Give the light a fixed IP (DHCP reservation) in your router so it stays reachable.")
                }
                Section("Details") {
                    LabeledContent("Device ID", value: l.id).textSelection(.enabled)
                    LabeledContent("Local key", value: l.localKey.map { $0.isEmpty ? "–" : "\($0.prefix(4))…" } ?? "–")
                    LabeledContent("Category", value: l.info.category)
                    if !l.info.productName.isEmpty { LabeledContent("Model", value: l.info.productName) }
                    LabeledContent("Controls", value: [l.canDim ? "dim" : nil, l.canTemp ? "white" : nil, l.canColour ? "colour" : nil].compactMap { $0 }.joined(separator: ", "))
                }
            }
        }
        .navigationTitle(light?.name ?? "Light")
        .onAppear {
            host = light?.host ?? ""
            version = light?.version ?? 0
        }
    }

    private func test() async {
        guard let l = store.lights.first(where: { $0.id == lightID }) else { return }
        testing = "Testing…"
        await LightControl.shared.drop(l.id)
        if let st = await LightControl.shared.localStatus(l) {
            testing = "Connected over Wi-Fi. \(st.count) data points read."
            store.lights = LightStore.load()
        } else {
            testing = "No answer. Check the IP, that the phone is on the same Wi-Fi, and that Smart Life isn't holding the light's only connection."
        }
    }
}
