import SwiftUI
import CoreLocation

/// Scene chips like Equinox: tap to run, long-press to edit, + to make one.
struct ScenesRow: View {
    @EnvironmentObject var store: AppStore
    @Binding var editing: LightScene?
    @State private var running: String?
    @State private var done: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Scenes")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.scenes) { s in chip(s) }
                    Button {
                        editing = LightScene(name: "", icon: "sparkles", states: [:])
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 48, height: 48)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
                    }
                    .foregroundStyle(.white)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ s: LightScene) -> some View {
        HStack(spacing: 8) {
            ZStack {
                if running == s.id { ProgressView().controlSize(.small) } else {
                    Image(systemName: done == s.id ? "checkmark" : s.icon)
                }
            }
            .frame(width: 18)
            Text(s.name).fontWeight(.semibold)
            if s.hasLocationTrigger {
                Image(systemName: "location.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(done == s.id ? Theme.accent.opacity(0.25) : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard running == nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            running = s.id
            Task {
                await store.run(s)
                running = nil
                done = s.id
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if done == s.id { done = nil }
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) { editing = s }
    }
}

struct SceneEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var scene: LightScene
    @State private var allMode: Bool
    @State private var confirmDelete = false
    @ObservedObject private var geo = Geo.shared

    static let icons = ["sparkles", "sun.max.fill", "sunset.fill", "moon.fill", "moon.zzz.fill", "tv.fill", "book.fill",
                        "fork.knife", "bed.double.fill", "sofa.fill", "desktopcomputer", "gamecontroller.fill",
                        "party.popper.fill", "heart.fill", "leaf.fill", "flame.fill", "house.fill", "figure.walk"]

    init(scene: LightScene) {
        _scene = State(initialValue: scene)
        _allMode = State(initialValue: scene.allState != nil)
    }

    private var isNew: Bool { !store.scenes.contains { $0.id == scene.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $scene.name)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(Self.icons, id: \.self) { i in
                            Image(systemName: i)
                                .frame(width: 38, height: 38)
                                .background(scene.icon == i ? Theme.accent.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                .onTapGesture { scene.icon = i }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Picker("Applies to", selection: $allMode) {
                        Text("All lights").tag(true)
                        Text("Pick lights").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: allMode) { _, all in
                        if all {
                            scene.allState = scene.allState ?? LightState(on: true, brightness: 0.6, temperature: 0.2)
                        } else {
                            scene.allState = nil
                        }
                    }
                } footer: {
                    Text(allMode ? "Every visible light, including ones you add later." : "Only the lights you include. Others are left alone.")
                }

                if allMode {
                    Section("Look") {
                        StateEditor(state: Binding(get: { scene.allState ?? LightState(on: true) }, set: { scene.allState = $0 }),
                                    canDim: true, canTemp: true, canColour: store.visible.contains(where: \.canColour))
                    }
                } else {
                    Section {
                        Button {
                            for l in store.visible { scene.states[l.id] = l.currentState }
                        } label: {
                            Label("Capture how the lights look now", systemImage: "camera.metering.center.weighted")
                        }
                    }
                    ForEach(store.visible) { l in
                        Section {
                            Toggle(isOn: Binding(get: { scene.states[l.id] != nil },
                                                 set: { scene.states[l.id] = $0 ? l.currentState : nil })) {
                                HStack {
                                    Circle().fill(l.tint).frame(width: 10, height: 10)
                                    Text(l.name)
                                }
                            }
                            if scene.states[l.id] != nil {
                                StateEditor(state: Binding(get: { scene.states[l.id] ?? LightState(on: true) },
                                                           set: { scene.states[l.id] = $0 }),
                                            canDim: l.canDim, canTemp: l.canTemp, canColour: l.canColour)
                            }
                        }
                    }
                }

                Section {
                    Toggle("When I arrive home", isOn: Binding(
                        get: { scene.onArrive == true },
                        set: { scene.onArrive = $0 ? true : nil; if $0 { geo.requestAccess() } }))
                    Toggle("When I leave home", isOn: Binding(
                        get: { scene.onLeave == true },
                        set: { scene.onLeave = $0 ? true : nil; if $0 { geo.requestAccess() } }))
                    if scene.hasLocationTrigger { HomeLocationRows() }
                } header: {
                    Text("Run automatically")
                } footer: {
                    Text("Uses iOS geofencing, so it fires even when Afterglow is closed. Location access has to be Always. For times of day use Shortcuts › Automation › Time of Day › Run Immediately › Afterglow \"Run Light Scene\". TV triggers live on the Apple Home bridge (Settings › TV & automations).")
                }

                if !isNew {
                    Section {
                        Button("Delete scene", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? "New scene" : scene.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if scene.name.trimmingCharacters(in: .whitespaces).isEmpty { scene.name = "Scene" }
                        store.saveScene(scene)
                        dismiss()
                        Task { await BridgeSync.pushIfChanged() }
                    }
                    .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await store.run(scene) }
                    } label: {
                        Label("Try it", systemImage: "play.fill")
                    }
                }
            }
            .confirmationDialog("Delete \(scene.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteScene(scene)
                    dismiss()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// On/off, brightness, and white or colour, for one scene target.
struct StateEditor: View {
    @Binding var state: LightState
    let canDim: Bool
    let canTemp: Bool
    let canColour: Bool

    var body: some View {
        Toggle("On", isOn: $state.on)
        if state.on {
            if canDim {
                VStack(alignment: .leading) {
                    Text("Brightness \(Int(((state.brightness ?? 1) * 100).rounded()))%").font(.subheadline)
                    Slider(value: Binding(get: { state.brightness ?? 1 }, set: { state.brightness = max(0.01, $0) }), in: 0.01...1)
                }
            }
            if canTemp || canColour {
                Picker("Light", selection: Binding(get: { state.hue != nil }, set: { colour in
                    if colour { state.hue = state.hue ?? 30; state.saturation = state.saturation ?? 1; state.temperature = nil }
                    else { state.hue = nil; state.saturation = nil; state.temperature = state.temperature ?? 0.2 }
                })) {
                    if canTemp { Text("White").tag(false) }
                    if canColour { Text("Colour").tag(true) }
                }
                .pickerStyle(.segmented)
                if let h = state.hue {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Hue").font(.subheadline)
                            Spacer()
                            Circle().fill(Color(hue: h / 360, saturation: state.saturation ?? 1, brightness: 1)).frame(width: 18, height: 18)
                        }
                        Slider(value: Binding(get: { state.hue ?? 0 }, set: { state.hue = $0 }), in: 0...359)
                            .tint(Color(hue: h / 360, saturation: 1, brightness: 1))
                        Text("Saturation").font(.subheadline)
                        Slider(value: Binding(get: { state.saturation ?? 1 }, set: { state.saturation = $0 }), in: 0...1)
                    }
                } else if canTemp {
                    VStack(alignment: .leading) {
                        Text("Warmth \(Kelvin.kelvin(state.temperature ?? 0.2)) K").font(.subheadline)
                        Slider(value: Binding(get: { state.temperature ?? 0.2 }, set: { state.temperature = $0 }), in: 0...1)
                            .tint(Kelvin.color(state.temperature ?? 0.2))
                    }
                }
            }
        }
    }
}

struct HomeLocationRows: View {
    @ObservedObject private var geo = Geo.shared
    @State private var radius: Double = 300

    var body: some View {
        if geo.auth == .denied || geo.auth == .restricted || geo.auth == .authorizedWhenInUse {
            VStack(alignment: .leading, spacing: 6) {
                Label(geo.auth == .authorizedWhenInUse
                      ? "Location is \"While Using\". Set it to Always or triggers won't fire in the background."
                      : "Location access is off for Afterglow.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
                Button("Open Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                }
                .font(.footnote)
            }
        }
        if let h = geo.home {
            LabeledContent("Home", value: String(format: "%.4f, %.4f", h.lat, h.lon)).font(.footnote)
        }
        Picker("Trigger distance", selection: Binding(
            get: { geo.home?.radius ?? radius },
            set: { r in radius = r; geo.setRadius(r) })) {
            Text("150 m").tag(150.0)
            Text("300 m").tag(300.0)
            Text("500 m").tag(500.0)
            Text("1 km").tag(1000.0)
            Text("2 km").tag(2000.0)
        }
        Button {
            geo.setHomeHere(radius: geo.home?.radius ?? radius)
        } label: {
            HStack {
                Label(geo.home == nil ? "Set home to where I am now" : "Move home to where I am now", systemImage: "house.fill")
                if geo.locating { Spacer(); ProgressView() }
            }
        }
        if let e = geo.lastEvent {
            Text("Last trigger: \(e)").font(.caption).foregroundStyle(.secondary)
        }
    }
}
