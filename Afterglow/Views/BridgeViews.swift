import SwiftUI

struct HomeBridgeView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var finder = BridgeFinder()
    @State private var cfg = BridgeConfig.stored
    @State private var info: BridgeInfo?
    @State private var status: String?
    @State private var busy = false
    @State private var manualHost = ""
    private let firmware = URL(string: "https://github.com/soum91/afterglow/releases/tag/firmware-latest")!
    private let guide = URL(string: "https://github.com/soum91/afterglow/tree/main/Bridge")!
    private let flasher = URL(string: "https://soum91.github.io/afterglow/")!

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "homekit").font(.largeTitle).foregroundStyle(Theme.accent)
                    Text("Apple doesn't let an iPhone app add lights to the Home app, and Home automations need a HomePod or Apple TV. The bridge solves both: a ~$10 ESP32 that puts your Tuya lights in Apple Home (local Wi-Fi, no cloud) and runs the TV automations itself, 24/7, no hub needed.")
                        .font(.subheadline)
                }
                .padding(.vertical, 6)
            }

            if cfg.isSet {
                Section("Your bridge") {
                    LabeledContent("Address", value: "\(cfg.host):\(cfg.port)")
                    if let i = info {
                        LabeledContent("Firmware", value: i.version ?? "?")
                        LabeledContent("Lights in Apple Home", value: "\(i.lights?.count ?? 0)")
                        if let tv = i.tv?.state { LabeledContent("TV", value: tv) }
                        if let d = i.learnedDelay {
                            LabeledContent("Learned TV-off delay", value: "\(d) s from \(i.samples ?? 0) evenings")
                        }
                        ForEach(i.lights ?? []) { l in
                            HStack {
                                Circle().fill(l.ok == false ? Theme.danger : (l.on == true ? Theme.accent : Theme.off)).frame(width: 8, height: 8)
                                Text(l.name)
                                Spacer()
                                Text(l.ok == false ? "not answering" : l.on == true ? "\(l.bri ?? 100)%" : "off").foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                        }
                    }
                    Button {
                        Task { await send(force: true) }
                    } label: {
                        Label(busy ? "Sending…" : "Send lights and automations", systemImage: "arrow.up.circle")
                    }
                    .disabled(busy)
                    Button("Refresh status") { Task { await loadInfo() } }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                    if let events = info?.events, !events.isEmpty {
                        DisclosureGroup("Recent events") {
                            ForEach(events.reversed(), id: \.self) { Text($0).font(.caption.monospaced()) }
                        }
                    }
                    Button("Forget this bridge", role: .destructive) {
                        cfg = BridgeConfig()
                        BridgeConfig.stored = cfg
                        info = nil
                    }
                }
            } else {
                Section {
                    if finder.searching { HStack { ProgressView(); Text("Looking for the bridge…") } }
                    ForEach(finder.found, id: \.host) { f in
                        Button {
                            Task { await pair(host: f.host, port: f.port) }
                        } label: {
                            LabeledContent(f.name, value: f.host)
                        }
                    }
                    Button("Search again") { finder.start() }
                    HStack {
                        TextField("Or type its IP", text: $manualHost).keyboardType(.decimalPad)
                        Button("Pair") { Task { await pair(host: manualHost.trimmingCharacters(in: .whitespaces), port: 8080) } }
                            .disabled(manualHost.isEmpty)
                    }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Pair")
                } footer: {
                    Text("Once the bridge is on your Wi-Fi it shows up here. Pairing hands it your lights' local keys and addresses; they never leave your network.")
                }
            }

            Section {
                step(1, "Get an ESP32 board", "Any ESP32, ESP32-S3 or ESP32-C3 dev board with USB. Power it from any USB charger.")
                step(2, "Flash the firmware", "On a computer, open soum91.github.io/afterglow in Chrome or Edge and tap Connect and install. It picks the right firmware for your board. Phones can't flash.")
                step(3, "Join its Wi-Fi", "Join \"HomeSpan-Setup\" (password homespan), enter your 2.4 GHz Wi-Fi and a setup code.")
                step(4, "Pair it here", "Come back to this screen. Afterglow finds it and sends your lights.")
                step(5, "Add to Home", "Home app › + › Add Accessory › More options › \"Afterglow Bridge\", enter the setup code (default 466-37-726).")
            } header: { Text("Setup") }

            Section {
                Link(destination: firmware) { Label("Firmware download", systemImage: "arrow.down.circle") }
                Link(destination: flasher) { Label("Web installer (open on a computer)", systemImage: "bolt.horizontal.circle") }
                Link(destination: guide) { Label("Full guide", systemImage: "book") }
            }
        }
        .navigationTitle("Apple Home")
        .onAppear {
            cfg = BridgeConfig.stored
            if cfg.isSet { Task { await loadInfo() } } else { finder.start() }
        }
        .onDisappear { finder.stop() }
    }

    private func pair(host: String, port: Int) async {
        guard !host.isEmpty else { return }
        busy = true
        defer { busy = false }
        var c = BridgeConfig(host: host, port: port)
        do {
            let i = try await BridgeAPI.info(c)
            if i.claimed == true && c.token.isEmpty {
                status = "This bridge is already paired with another phone. Type @R in its serial console to reset it."
                return
            }
            c.token = try await BridgeAPI.claim(c)
            BridgeConfig.stored = c
            cfg = c
            info = i
            await send(force: true)
        } catch {
            status = "Couldn't pair: \(error.localizedDescription)"
        }
    }

    private func send(force: Bool) async {
        busy = true
        defer { busy = false }
        let missing = store.visible.filter { !$0.hasLocal }
        status = await BridgeSync.pushIfChanged(force: force)
        if !missing.isEmpty {
            status = (status ?? "") + " Not sent (no Wi-Fi address yet): " + missing.map(\.name).joined(separator: ", ") + ". Run Find lights on Wi-Fi first."
        }
        cfg = BridgeConfig.stored
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await loadInfo()
    }

    private func loadInfo() async {
        do { info = try await BridgeAPI.info(cfg) } catch { status = "Bridge not answering: \(error.localizedDescription)" }
    }

    private func step(_ n: Int, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.headline).foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AutomationsView: View {
    @EnvironmentObject var store: AppStore
    @State private var auto = Automations.stored
    @State private var tv = TVConfig.stored
    @State private var tvTest: String?
    @State private var saved: String?

    var body: some View {
        Form {
            Section {
                TextField("TV IP address", text: $tv.host).keyboardType(.decimalPad)
                SecureField("Pre-shared key (only if you set one)", text: $tv.psk)
                Button("Test") {
                    TVConfig.stored = tv
                    tvTest = "Asking the TV…"
                    Task {
                        let p = await TV.power(tv)
                        tvTest = "TV says: \(p.label)"
                        store.tvPower = p
                    }
                }
                if let tvTest { Text(tvTest).font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Sony TV")
            } footer: {
                Text("On the TV: Settings › Network & Internet › Home network › IP control › Authentication: Normal and Pre-Shared Key, and turn on Remote start. Give the TV a fixed IP in your router.")
            }

            Section {
                Toggle("When the TV turns off", isOn: $auto.tvOffEnabled)
                if auto.tvOffEnabled {
                    scenePicker("Do", selection: $auto.tvOffScene, noneLabel: "Turn all lights off")
                    Picker("After", selection: $auto.tvOffDelay) {
                        Text("Learn from me").tag(-1)
                        Text("Right away").tag(0)
                        Text("30 seconds").tag(30)
                        Text("1 minute").tag(60)
                        Text("2 minutes").tag(120)
                        Text("5 minutes").tag(300)
                    }
                    Toggle("Only at night", isOn: $auto.tvOffWindow)
                    if auto.tvOffWindow {
                        DatePicker("From", selection: timeBinding($auto.tvOffFrom), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: timeBinding($auto.tvOffTo), displayedComponents: .hourAndMinute)
                    }
                }
            } header: {
                Text("TV off")
            } footer: {
                Text("\"Learn from me\" starts at 60 s, then watches how long you usually wait after the TV goes off before turning the lights off yourself (from Home, this app, Smart Life or the wall) and uses your typical gap. Turn the TV back on during the wait and nothing happens.")
            }

            Section {
                Toggle("When the TV turns on", isOn: $auto.tvOnEnabled)
                if auto.tvOnEnabled {
                    scenePicker("Run", selection: $auto.tvOnScene, noneLabel: "Pick a scene")
                    Toggle("Only in the evening", isOn: $auto.tvOnWindow)
                    if auto.tvOnWindow {
                        DatePicker("From", selection: timeBinding($auto.tvOnFrom), displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: timeBinding($auto.tvOnTo), displayedComponents: .hourAndMinute)
                    }
                }
            } header: {
                Text("TV on")
            } footer: {
                Text("Good with Movie: dims everything when you start watching.")
            }

            Section {
                Toggle("Turn everything off late at night", isOn: $auto.lateOffEnabled)
                if auto.lateOffEnabled {
                    DatePicker("At", selection: timeBinding($auto.lateOffAt), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Catches lights left on when you fell asleep. Skipped while the TV is on.")
            }

            Section {
                Button("Save") { save() }.fontWeight(.semibold)
                if let saved { Text(saved).font(.footnote).foregroundStyle(.secondary) }
            } footer: {
                Text(BridgeConfig.stored.isSet ? "These run on your Apple Home bridge, so they work with your phone asleep or away." :
                        "These run on the Apple Home bridge. Until you set one up, use Shortcuts: Automation › Time of Day › Afterglow \"Lights Off If TV Is Off\".")
            }
        }
        .navigationTitle("TV & automations")
    }

    private func scenePicker(_ title: String, selection: Binding<String?>, noneLabel: String) -> some View {
        Picker(title, selection: selection) {
            Text(noneLabel).tag(String?.none)
            ForEach(store.scenes) { s in Text(s.name).tag(String?.some(s.id)) }
        }
    }

    private func save() {
        TVConfig.stored = tv
        Automations.stored = auto
        saved = "Saved."
        Task {
            await store.refreshTV()
            if let r = await BridgeSync.pushIfChanged() { saved = r }
        }
    }
}

struct ShortcutsGuideView: View {
    var body: some View {
        Form {
            Section("Just say it") {
                phrase("Hey Siri, lights off in Afterglow")
                phrase("Hey Siri, lights on in Afterglow")
                phrase("Hey Siri, Afterglow Movie", note: "Any scene by name")
                phrase("Hey Siri, toggle Desk lamp in Afterglow")
                phrase("Hey Siri, bedtime in Afterglow", note: "Lights off unless the TV is on")
            }
            Section {
                Text("Every time you turn lights off or run a scene in Afterglow, it tells Siri. After a few days Siri suggests \"Lights Off\" on the lock screen and in Spotlight around the time you usually do it.")
                    .font(.footnote)
            } header: { Text("Learns your habits") }

            Section {
                recipe("Sleep focus turns on", "Lights Off If TV Is Off")
                recipe("Charger connected, 11 pm–5 am", "Lights Off If TV Is Off")
                recipe("Alarm is stopped", "Run Light Scene › Bright")
                recipe("Sunset", "Run Light Scene › Evening")
                recipe("Leave home (or use the scene's own trigger)", "Turn All Lights Off")
            } header: {
                Text("Shortcuts automations")
            } footer: {
                Text("Shortcuts › Automation › New Automation, pick the trigger, choose Run Immediately, then add the Afterglow action. These run on the phone, no hub needed.")
            }

            Section {
                Text("With the bridge in Apple Home, Siri also understands plain Home phrases with no app name: \"turn off the bedroom light\", \"set the strip to blue\", \"dim the desk lamp to 20 percent\".")
                    .font(.footnote)
            } header: { Text("With the Apple Home bridge") }
        }
        .navigationTitle("Siri & Shortcuts")
    }

    private func phrase(_ text: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\u{201C}\(text)\u{201D}").font(.subheadline)
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func recipe(_ when: String, _ action: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(when).font(.subheadline.weight(.semibold))
            Text(action).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WidgetsGuideView: View {
    var body: some View {
        Form {
            Section("Home and lock screen") {
                Text("Long-press the home screen › Edit › Add Widget › Afterglow. Small: all lights on/off. Medium and large: one button per light. Lock screen: an all-lights toggle and a lights-on count. The buttons work without opening the app.")
                    .font(.footnote)
            }
            Section("Control Center") {
                Text("Open Control Center › + › Add a Control › Afterglow. Add \"Light\" once per light (tap it while editing to pick which one, or leave it on All lights), and \"Scene\" for one-tap scenes. These also work from the lock screen's corner buttons and the Action button.")
                    .font(.footnote)
            }
            Section {
                LabeledContent("Shared storage", value: AppGroup.isShared ? "Working" : "Not available")
            } footer: {
                Text(AppGroup.isShared ? "Widgets read your lights from the shared App Group." :
                        "Your sideloader stripped the App Group, so widgets can't see your lights. Reinstall with app extensions kept (AltStore, SideStore or Sideloadly with \"keep extensions\").")
            }
        }
        .navigationTitle("Widgets")
    }
}
