import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var detail: String?
    @State private var showSettings = false
    @State private var editing: LightScene?

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
                        allBar
                        ScenesRow(editing: $editing)
                        lightsGrid
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
            .sheet(item: $editing) { s in SceneEditor(scene: s) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Afterglow").font(.system(size: 34, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    let on = store.visible.filter(\.isOn).count
                    Text(store.visible.isEmpty ? "No lights yet" : on == 0 ? "All off" : "\(on) of \(store.visible.count) on")
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
            bigButton("All off", "lightbulb.slash.fill", active: !store.anyOn) { store.setAll(on: false) }
            bigButton("All on", "lightbulb.2.fill", active: store.anyOn && store.visible.allSatisfy(\.isOn)) { store.setAll(on: true) }
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
            SectionTitle(text: "Lights")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(store.visible) { l in
                    LightTile(light: l, route: store.routes[l.id]) {
                        store.toggle(l)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } open: {
                        detail = l.id
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "lightbulb").font(.largeTitle).foregroundStyle(.secondary)
            Text("No lights found in your Smart Life account.").foregroundStyle(.secondary)
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

    var body: some View {
        let on = light.isOn
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    Circle().fill(on ? light.tint : Color.white.opacity(0.1)).frame(width: 40, height: 40)
                    Image(systemName: on ? "lightbulb.fill" : "lightbulb")
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
        .frame(height: 132)
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
