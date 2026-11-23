import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var detail: String?
    @State private var showSettings = false
    @State private var editing: LightScene?
    @State private var editingLayout = false
    @State private var showCustomize = false
    @State private var layout = HomeDashboardOptions.load()

    private var glow: Color {
        let on = store.visible.filter(\.isOn)
        return on.first?.tint ?? Theme.accent
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Theme.background(glow, strength: store.anyOn ? 0.28 : 0.12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        if layout.showBulkActions { allBar }
                        if layout.showScenes { ScenesRow(editing: $editing) }
                        lightsGrid
                        if layout.showIntegrations {
                            HomeIntegrationCards(showKeystone: layout.showKeystone, showSurge: layout.showSurge)
                        }
                        if store.visible.isEmpty && !store.loading { emptyState }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 80)
                }
                .refreshable { await store.reloadDevices() }

                if let t = store.toast {
                    Text(t)
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 20)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { store.toast = nil }
                }
            }
            .animation(.spring(duration: 0.3), value: store.toast)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: Binding(get: { detail.map(IDBox.init) }, set: { detail = $0?.id })) { box in
                LightDetailView(lightID: box.id)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showCustomize) {
                HomeCustomizeView(options: $layout)
                    .environmentObject(store)
            }
            .onChange(of: layout) { _, value in value.save() }
            .sheet(item: $editing) { s in SceneEditor(scene: s) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Afterglow").font(.system(size: 34, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    let on = store.groupLights.filter(\.isOn).count
                    Text(store.groupLights.isEmpty ? "No lights in group" : on == 0 ? "Lights off" : "\(on) of \(store.groupLights.count) lights on")
                        .foregroundStyle(.secondary)
                    if let p = store.tvPower {
                        Label(p.isOn ? "TV on" : "TV off", systemImage: p.isOn ? "tv.fill" : "tv")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.card, in: Capsule())
                            .foregroundStyle(p.isOn ? Theme.accent : .secondary)
                    }
                    if let f = store.finding {
                        ProgressView().controlSize(.mini)
                        Text(f).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .font(.subheadline)
            }
            Spacer()
            HStack(spacing: 8) {
                Button { editingLayout.toggle() } label: {
                    Image(systemName: editingLayout ? "checkmark.circle.fill" : "square.grid.2x2")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Theme.card, in: Circle())
                }
                .accessibilityLabel(editingLayout ? "Finish arranging cards" : "Arrange Home cards")
                Button { showCustomize = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Theme.card, in: Circle())
                }
                .accessibilityLabel("Customize Home")
            }
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
            }
            .foregroundStyle(.white)
        }
        .padding(.top, 12)
    }

    private var allBar: some View {
        HStack(spacing: 10) {
            bigButton("Lights off", "lightbulb.slash.fill", active: !store.anyOn) { store.setAll(on: false) }
            bigButton("Lights on", "lightbulb.2.fill", active: store.anyOn && store.groupLights.allSatisfy(\.isOn)) { store.setAll(on: true) }
        }
    }

    private func bigButton(_ title: String, _ icon: String, active: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { action(); UIImpactFeedbackGenerator(style: .medium).impactOccurred() }) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(active ? Theme.accent.opacity(0.22) : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(active ? Theme.accent.opacity(0.5) : Theme.stroke))
        }
        .foregroundStyle(.white)
    }

    private var lightsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.groupLights.isEmpty {
                SectionTitle(text: "Lights")
                deviceTiles(store.groupLights)
            }
            if !store.otherDevices.isEmpty {
                SectionTitle(text: "Other devices · excluded from All Lights")
                deviceTiles(store.otherDevices)
            }
        }
    }

    private func rows(_ devices: [Light]) -> [[Light]] {
        var output: [[Light]] = []
        var pair: [Light] = []
        for l in devices {
            if l.resolvedCardSize != .compact {
                if !pair.isEmpty { output.append(pair); pair = [] }
                output.append([l])
            } else {
                pair.append(l)
                if pair.count == 2 { output.append(pair); pair = [] }
            }
        }
        if !pair.isEmpty { output.append(pair) }
        return output
    }

    private func deviceTiles(_ devices: [Light]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(Array(rows(devices).enumerated()), id: \.offset) { group in
                GridRow {
                    ForEach(group.element) { light in
                        displayCard(light)
                            .gridCellColumns(light.resolvedCardSize == .compact ? 1 : 2)
                    }
                    if group.element.count == 1 && group.element[0].resolvedCardSize == .compact {
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func displayCard(_ l: Light) -> some View {
        let tile = LightTile(light: l, route: store.routes[l.id],
                             toggle: {
                                 if !editingLayout {
                                     store.toggle(l)
                                     UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                 }
                             }, open: {
                                 if !editingLayout { detail = l.id }
                             }, tileHeight: l.resolvedCardSize.height)
        if editingLayout {
            tile
                .onDrag { NSItemProvider(object: l.id as NSString) }
                .onDrop(of: ["public.utf8-plain-text"], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { item, _ in
                        guard let source = item as? String else { return }
                        DispatchQueue.main.async {
                            store.moveLight(source, before: l.id)
                        }
                    }
                    return true
                }
                .overlay(alignment: .topTrailing) {
                    Menu {
                        ForEach(HomeCardSize.allCases, id: \.self) { size in
                            Button(size.name, systemImage: size == l.resolvedCardSize ? "checkmark" : "rectangle.grid.1x2") {
                                store.updateLight(l.id) { $0.cardSize = size }
                            }
                        }
                        Divider()
                        Button("Move earlier", systemImage: "arrow.up") { store.stepLight(l.id, forward: false) }
                        Button("Move later", systemImage: "arrow.down") { store.stepLight(l.id, forward: true) }
                        Button("Device settings", systemImage: "gearshape") { detail = l.id }
                    } label: {
                        Image(systemName: "rectangle.expand.vertical")
                            .font(.caption.bold())
                            .frame(width: 36, height: 36)
                            .background(.regularMaterial, in: Circle())
                    }
                    .padding(7)
                }
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        } else {
            tile
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb").font(.largeTitle).foregroundStyle(.secondary)
            Text("No lights found on your Tuya Smart account.").foregroundStyle(.secondary)
            Button("Check again") { Task { await store.reloadDevices() } }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

struct IDBox: Identifiable { let id: String }

struct LightTile: View {
    let light: Light
    let route: Route?
    let toggle: () -> Void
    let open: () -> Void
    var tileHeight: CGFloat = 132

    var body: some View {
        let on = light.isOn
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    Circle().fill(on ? light.tint : Color.white.opacity(0.1)).frame(width: 40, height: 40)
                    Image(systemName: light.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(on ? Color.black.opacity(0.75) : .white.opacity(0.7))
                }
                .shadow(color: on ? light.tint.opacity(0.6) : .clear, radius: 10)
                Spacer()
                Button(action: open) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .foregroundStyle(.white.opacity(0.8))
            }
            Spacer(minLength: 14)
            Text(light.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(2)
            HStack(spacing: 5) {
                Text(!light.online ? "Offline" : on ? (light.canDim ? "\(light.percent)%" : "On") : "Off")
                if let route {
                    Image(systemName: route == .local ? "wifi" : "cloud")
                        .font(.system(size: 10, weight: .bold))
                        .opacity(0.6)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(height: tileHeight)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(on ? light.tint.opacity(0.10 + 0.22 * light.brightness) : Theme.card)
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(on ? light.tint.opacity(0.35) : Theme.stroke))
        .opacity(light.online ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture(perform: toggle)
        .onLongPressGesture(minimumDuration: 0.35, perform: open)
        .animation(.easeInOut(duration: 0.2), value: on)
    }
}
