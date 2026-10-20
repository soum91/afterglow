import SwiftUI

struct LightDetailView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let lightID: String
    @State private var tab: Tab = .white
    @State private var showInfo = false

    enum Tab: String, CaseIterable { case white = "White", colour = "Colour" }

    private var light: Light? { store.lights.first { $0.id == lightID } }

    var body: some View {
        ZStack {
            Theme.background(light?.isOn == true ? (light?.tint ?? Theme.accent) : Theme.off, strength: 0.3)
            if let l = light {
                ScrollView {
                    VStack(spacing: 22) {
                        top(l)
                        HStack(alignment: .center, spacing: 24) {
                            if l.canDim {
                                BrightnessSlider(value: l.isOn ? l.brightness : 0, tint: l.tint) { v in
                                    store.set(l, LightState(on: true, brightness: max(0.01, v)))
                                }
                                .frame(width: 120, height: 320)
                            } else {
                                PowerOrb(on: l.isOn, tint: l.tint) { store.toggle(l) }
                                    .frame(width: 160, height: 160)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if l.canTemp && l.canColour {
                            Picker("Mode", selection: $tab) {
                                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                        }
                        if (tab == .white || !l.canColour) && l.canTemp {
                            whiteControls(l)
                        } else if l.canColour {
                            colourControls(l)
                        }
                        infoCard(l)
                    }
                    .padding(20)
                }
                .onAppear { tab = l.isColourMode ? .colour : .white }
            } else {
                Text("This light is gone.").foregroundStyle(.secondary)
            }
        }
    }

    private func top(_ l: Light) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(l.name).font(.title2.bold())
                Text(!l.online ? "Offline" : l.isOn ? (l.canDim ? "\(l.percent)%\(l.isColourMode ? "" : l.temperature.map { " · \(Kelvin.kelvin($0)) K" } ?? "")" : "On") : "Off")
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                store.toggle(l)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 52, height: 52)
                    .background(l.isOn ? Color.white : Theme.card, in: Circle())
                    .foregroundStyle(l.isOn ? Color.black : .white)
            }
        }
    }

    // MARK: White

    private func whiteControls(_ l: Light) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Temperature")
            GradientSlider(value: l.isColourMode ? 0.3 : (l.temperature ?? 0.3),
                           colors: [Kelvin.color(0), Kelvin.color(0.5), Kelvin.color(1)]) { t in
                store.set(l, LightState(on: true, temperature: t))
            }
            HStack {
                ForEach(Self.presets.indices, id: \.self) { i in
                    let t = Self.presets[i].0, name = Self.presets[i].1
                    Button {
                        store.set(l, LightState(on: true, temperature: t))
                    } label: {
                        VStack(spacing: 6) {
                            Circle().fill(Kelvin.color(t)).frame(width: 34, height: 34)
                                .overlay(Circle().stroke(.white.opacity(0.25)))
                            Text(name).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .card()
    }

    static let presets: [(Double, String)] = [(0.0, "Candle"), (0.2, "Warm"), (0.5, "Neutral"), (1.0, "Daylight")]

    // MARK: Colour

    private func colourControls(_ l: Light) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "Colour")
            ColourWheel(hue: l.colour?.h ?? 30, saturation: l.isColourMode ? (l.colour?.s ?? 1) : 0) { h, s in
                store.set(l, LightState(on: true, hue: h, saturation: s))
            }
            .frame(width: 260, height: 260)
            .frame(maxWidth: .infinity)
            HStack {
                ForEach([0.0, 25, 50, 130, 200, 240, 280, 320], id: \.self) { h in
                    Button {
                        store.set(l, LightState(on: true, hue: h, saturation: 1))
                    } label: {
                        Circle().fill(Color(hue: h / 360, saturation: 1, brightness: 1)).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.white.opacity(0.25)))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    // MARK: Info

    private func infoCard(_ l: Light) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Connection")
            if l.hasLocal, let host = l.host {
                Label("Wi-Fi \(host) · protocol \(l.version.map { String(format: "%.1f", $0) } ?? "auto")", systemImage: "wifi")
            } else {
                Label("Cloud only. Use Settings › Find lights on Wi-Fi for instant local control.", systemImage: "cloud")
            }
            if let r = store.routes[l.id] {
                Text("Last command went over \(r == .local ? "Wi-Fi" : "the cloud").").foregroundStyle(.secondary)
            }
            Text("\(l.info.productName.isEmpty ? "Tuya light" : l.info.productName) · \(l.info.category)")
                .foregroundStyle(.secondary)
            DisclosureGroup("Data points", isExpanded: $showInfo) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(l.status.keys.sorted(), id: \.self) { k in
                        HStack {
                            Text(k).foregroundStyle(.secondary)
                            Spacer()
                            Text(l.status[k]?.display ?? "").lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .font(.caption.monospaced())
                .padding(.top, 6)
            }
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: - Controls

/// Control Center style vertical brightness pill.
struct BrightnessSlider: View {
    let value: Double
    let tint: Color
    let onChange: (Double) -> Void
    @State private var drag: Double?
    @State private var start: Double = 0

    var body: some View {
        GeometryReader { geo in
            let v = drag ?? value
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.white.opacity(0.1))
                Rectangle()
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .bottom, endPoint: .top))
                    .frame(height: geo.size.height * v)
                Text("\(max(v > 0 ? 1 : 0, Int((v * 100).rounded())))%")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(v > 0.18 ? Color.black.opacity(0.7) : .white)
                    .padding(.bottom, 16)
                    .contentTransition(.numericText())
            }
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(Theme.stroke))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if drag == nil { start = value }
                        let next = max(0.01, min(1, start - g.translation.height / geo.size.height))
                        if abs(next - (drag ?? -1)) >= 0.01 {
                            drag = next
                            onChange(next)
                        }
                    }
                    .onEnded { _ in
                        if let d = drag { onChange(d) }
                        drag = nil
                    }
            )
        }
    }
}

struct GradientSlider: View {
    let value: Double
    let colors: [Color]
    let onChange: (Double) -> Void
    @State private var drag: Double?

    var body: some View {
        GeometryReader { geo in
            let v = drag ?? value
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                Circle()
                    .fill(.white)
                    .frame(width: 30, height: 30)
                    .shadow(radius: 3)
                    .offset(x: (geo.size.width - 30) * v)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let next = max(0, min(1, (g.location.x - 15) / (geo.size.width - 30)))
                        if abs(next - (drag ?? -1)) >= 0.01 { drag = next; onChange(next) }
                    }
                    .onEnded { _ in
                        if let d = drag { onChange(d) }
                        drag = nil
                    }
            )
        }
        .frame(height: 34)
    }
}

/// Hue around, saturation outward.
struct ColourWheel: View {
    let hue: Double
    let saturation: Double
    let onChange: (Double, Double) -> Void
    @State private var drag: (Double, Double)?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2
            let hs = drag ?? (hue, saturation)
            let h = hs.0, s = hs.1
            let angle = h / 360 * 2 * .pi
            ZStack {
                Circle().fill(AngularGradient(colors: stride(from: 0.0, through: 360, by: 30).map { Color(hue: $0 / 360, saturation: 1, brightness: 1) },
                                              center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: r))
                Circle()
                    .fill(Color(hue: h / 360, saturation: max(0.05, s), brightness: 1))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
                    .shadow(radius: 4)
                    .offset(x: cos(angle) * s * (r - 17), y: sin(angle) * s * (r - 17))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let dx = g.location.x - r, dy = g.location.y - r
                        var deg = atan2(dy, dx) * 180 / .pi
                        if deg < 0 { deg += 360 }
                        let sat = max(0, min(1, sqrt(dx * dx + dy * dy) / (r - 17)))
                        let next: (Double, Double) = (Double(deg), Double(sat))
                        if let d = drag, abs(d.0 - next.0) < 2, abs(d.1 - next.1) < 0.02 { return }
                        drag = next
                        onChange(next.0, next.1)
                    }
                    .onEnded { _ in
                        if let d = drag { onChange(d.0, d.1) }
                        drag = nil
                    }
            )
        }
    }
}

struct PowerOrb: View {
    let on: Bool
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(on ? tint : Color.white.opacity(0.1))
                Image(systemName: "power").font(.system(size: 44, weight: .bold))
                    .foregroundStyle(on ? Color.black.opacity(0.7) : .white)
            }
            .shadow(color: on ? tint.opacity(0.6) : .clear, radius: 24)
        }
        .buttonStyle(.plain)
    }
}
