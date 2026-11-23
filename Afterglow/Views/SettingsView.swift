import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var reconnecting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { LightsManageView() } label: {
                        LabeledContent("Lights", value: "\(store.visible.count) shown")
                    }
                    NavigationLink { AddDevicesView() } label: {
                        Label("Add, remove or restore devices", systemImage: "plus.circle")
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

                Section("Home location") {
                    HomeLocationRows()
                }

                Section("About") {
                    LabeledContent("Installed version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")
                }

                Section("Tuya Smart authorization") {
                    Button {
                        reconnecting = true
                    } label: {
                        Label("Reconnect Tuya Smart", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Text("Uses a rotating Tuya cloud access token, not Safari cookies. Reconnecting doesn't erase your saved local device settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Button("Sign out of Tuya Smart", role: .destructive) {
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
        .sheet(isPresented: $reconnecting) {
            LoginView().environmentObject(store)
                .onChange(of: store.token?.refreshToken) { _, new in
                    if new != nil { reconnecting = false }
                }
        }
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
                            Image(systemName: l.hidden ? "eye.slash" : l.iconName)
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
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

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
                    Picker("Device icon", selection: Binding(
                        get: { l.customIcon ?? "" },
                        set: { symbol in store.updateLight(l.id) { $0.customIcon = symbol.isEmpty ? nil : symbol } }
                    )) {
                        Label("Automatic", systemImage: "wand.and.stars").tag("")
                        Label("Light bulb", systemImage: "lightbulb.fill").tag("lightbulb.fill")
                        Label("Ceiling light", systemImage: "lightbulb.fill").tag("light.recessed.fill")
                        Label("Power strip", systemImage: "poweroutlet.strip.fill").tag("poweroutlet.strip.fill")
                        Label("Power outlet", systemImage: "poweroutlet.type.b").tag("poweroutlet.type.b")
                        Label("Smart switch", systemImage: "switch.2").tag("switch.2")
                        Label("Lamp", systemImage: "lamp.desk.fill").tag("lamp.desk.fill")
                        Label("Fan", systemImage: "fan.fill").tag("fan.fill")
                    }
                } header: { Text("Appearance") } footer: {
                    Text("Changes the icon in Afterglow. Apple Home's accessory category comes from the Keystone bridge and is configured separately.")
                }
                Section("Bulk actions") {
                    Toggle("Include in All Lights and bulk scenes", isOn: Binding(
                        get: { l.belongsToAllLights },
                        set: { flag in
                            store.updateLight(l.id) { $0.includeInAllLights = flag }
                            Task { await BridgeSync.pushIfChanged(force: true) }
                        }
                    ))
                } footer: {
                    Text("Off keeps this device controllable individually but protects it from All On, All Off, Siri's All Lights commands, default light scenes, and TV/bedtime light automations.")
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
                Section {
                    Button("Remove device from Afterglow", role: .destructive) { confirmRemove = true }
                } footer: {
                    Text("Removes this device from Afterglow, widgets, and Afterglow Shortcuts without switching off the actual Tuya device. Any separately configured Keystone accessory must be managed in Keystone.")
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
        .navigationTitle(light?.name ?? "Device")
        .confirmationDialog("Remove this device from Afterglow?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove from Afterglow", role: .destructive) {
                Task {
                    await store.removeDevice(lightID)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This only removes it from Afterglow. The physical Tuya device will stay powered and paired to Tuya Smart.")
        }
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


/// Smart switches and plugs from Smart Life that have a light behind them, added by hand.
struct AddDevicesView: View {
    @EnvironmentObject var store: AppStore
    @State private var busy: String?

    private func kind(_ d: DeviceInfo) -> String {
        switch d.category {
        case "kg", "tdq", "kgq": return "Switch"
        case "cz", "pc": return "Plug"
        case "dlq", "znjdq": return "Breaker"
        default: return "On/off device"
        }
    }

    var body: some View {
        List {
            Section {
                if store.addable.isEmpty {
                    Text(store.loading ? "Looking at your Tuya Smart devices…" : "No new switches or plugs available. Devices already added appear in Settings → Lights; removed devices can be restored below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.addable) { d in
                    HStack {
                        Image(systemName: d.category == "cz" || d.category == "pc" ? "poweroutlet.type.b" : "switch.2")
                            .foregroundStyle(.secondary).frame(width: 26)
                        VStack(alignment: .leading) {
                            Text(d.name)
                            Text("\(kind(d))\(d.online ? "" : " · offline")").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if busy == d.id { ProgressView() } else {
                            Button("Add") {
                                busy = d.id
                                Task { await store.include(d.id, true); busy = nil }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("Available on Tuya Smart")
            } footer: {
                Text("Added devices stay individually controllable. Plugs, power strips and switches are excluded from All Lights, Siri bulk commands and bedtime scenes unless you explicitly enable them in the device's Bulk actions settings.")
            }

            let added = store.lights.filter { DeviceInfo.included.contains($0.id) }
            if !added.isEmpty {
                Section("Added by hand") {
                    ForEach(added) { l in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.name)
                                if let why = store.bridgeProblem(l) {
                                    Text("Cloud only, not on the bridge: \(why)").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text("On Wi-Fi at \(l.host ?? "") · goes to the bridge").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remove", role: .destructive) { Task { await store.removeDevice(l.id) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            if !store.removedDevices.isEmpty {
                Section("Removed devices") {
                    ForEach(store.removedDevices) { d in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(d.name)
                                Text(kind(d)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { Task { await store.restoreDevice(d.id) } }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .navigationTitle("Add / remove devices")
        .refreshable { await store.reloadDevices() }
        .task { if store.addable.isEmpty { await store.reloadDevices() } }
    }
}
