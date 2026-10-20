import WidgetKit
import SwiftUI
import AppIntents

@main
struct AfterglowWidgets: WidgetBundle {
    var body: some Widget {
        LightsWidget()
        LightToggleControl()
        SceneButtonControl()
    }
}

// MARK: - Timeline

struct LightsEntry: TimelineEntry {
    let date: Date
    let lights: [LightSnap]
    let signedIn: Bool
    let shared: Bool

    var onCount: Int { lights.filter(\.isOn).count }
    var anyOn: Bool { onCount > 0 }
    var glow: Color { lights.first(where: \.isOn)?.tint ?? Color(red: 1, green: 0.68, blue: 0.3) }

    static func make() -> LightsEntry {
        LightsEntry(date: .now, lights: LightStore.snaps(), signedIn: TokenStore.load() != nil, shared: AppGroup.isShared)
    }
    static let preview = LightsEntry(date: .now, lights: LightSnap.previews, signedIn: true, shared: true)
}

struct LightsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LightsEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (LightsEntry) -> Void) {
        let e = LightsEntry.make()
        completion(context.isPreview && e.lights.isEmpty ? .preview : e)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LightsEntry>) -> Void) {
        Task {
            await Lights.refresh()
            completion(Timeline(entries: [.make()], policy: .after(Date().addingTimeInterval(20 * 60))))
        }
    }
}

// MARK: - Widget

struct LightsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AfterglowLights", provider: LightsProvider()) { entry in
            LightsWidgetView(entry: entry)
                .containerBackground(for: .widget) { WidgetBG(entry: entry) }
        }
        .configurationDisplayName("Lights")
        .description("Your lights, one tap each.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct WidgetBG: View {
    let entry: LightsEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        if family.isAccessory {
            Color.clear
        } else {
            ZStack {
                LinearGradient(colors: [Color(red: 0.09, green: 0.08, blue: 0.08), Color(red: 0.03, green: 0.03, blue: 0.04)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [entry.glow.opacity(entry.anyOn ? 0.38 : 0.08), .clear],
                               center: .topLeading, startRadius: 5, endRadius: 260)
            }
        }
    }
}

extension WidgetFamily {
    var isAccessory: Bool { self == .accessoryCircular || self == .accessoryRectangular || self == .accessoryInline }
}

struct LightsWidgetView: View {
    let entry: LightsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.lights.isEmpty {
            empty
        } else {
            switch family {
            case .systemSmall: small
            case .systemMedium: grid(columns: 2, rows: 2)
            case .systemLarge: large
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .accessoryInline: Label("\(entry.onCount) light\(entry.onCount == 1 ? "" : "s") on", systemImage: "lightbulb.fill")
            default: small
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "lightbulb").font(.title2)
            Spacer()
            Text(!entry.shared ? "Widget can't see Afterglow's data. Reinstall with app extensions kept." :
                    entry.signedIn ? "Open Afterglow to load your lights." : "Open Afterglow to sign in.")
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white.opacity(0.8))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: entry.anyOn ? "lightbulb.2.fill" : "lightbulb.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(entry.anyOn ? entry.glow : .white.opacity(0.6))
                Spacer()
            }
            Spacer(minLength: 0)
            Text(entry.anyOn ? "\(entry.onCount) on" : "All off")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("\(entry.lights.count) light\(entry.lights.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.bottom, 8)
            Button(intent: SetLightPowerIntent(light: .all, on: !entry.anyOn)) {
                Text(entry.anyOn ? "Turn off" : "Turn on")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(entry.anyOn ? Color.white : Color.white.opacity(0.14), in: Capsule())
                    .foregroundStyle(entry.anyOn ? Color.black : .white)
            }
            .buttonStyle(.plain)
        }
    }

    private func grid(columns: Int, rows: Int) -> some View {
        let shown = Array(entry.lights.prefix(columns * rows))
        return Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { r in
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        let i = r * columns + c
                        if i < shown.count { LightButton(snap: shown[i]) } else { Color.clear }
                    }
                }
            }
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Afterglow").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Button(intent: SetLightPowerIntent(light: .all, on: false)) {
                    Label("All off", systemImage: "lightbulb.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            grid(columns: 2, rows: 3)
            let scenes = Array(SceneStore.load().prefix(3))
            if !scenes.isEmpty {
                HStack(spacing: 6) {
                    ForEach(scenes) { s in
                        Button(intent: RunSceneIntent(scene: SceneEntity(s))) {
                            Label(s.name, systemImage: s.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.1), in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var circular: some View {
        Button(intent: SetLightPowerIntent(light: .all, on: !entry.anyOn)) {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.anyOn ? "lightbulb.fill" : "lightbulb").font(.system(size: 18, weight: .semibold))
                    Text("\(entry.onCount)").font(.system(size: 12, weight: .bold))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(entry.anyOn ? "\(entry.onCount) on" : "All off", systemImage: entry.anyOn ? "lightbulb.fill" : "lightbulb")
                .font(.headline)
            Text(entry.lights.filter(\.isOn).map(\.name).joined(separator: ", ").ifEmpty("Lights"))
                .font(.caption)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LightButton: View {
    let snap: LightSnap
    var body: some View {
        Button(intent: ToggleLightIntent(light: LightEntity(id: snap.id, name: snap.name))) {
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: snap.isOn ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(snap.isOn ? Color.black.opacity(0.7) : .white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(snap.isOn ? snap.tint : Color.white.opacity(0.1), in: Circle())
                Spacer(minLength: 0)
                Text(snap.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(!snap.online ? "Offline" : snap.isOn ? (snap.canDim ? "\(snap.percent)%" : "On") : "Off")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(snap.isOn ? snap.tint.opacity(0.22) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

// MARK: - Control Center

struct LightControlValue {
    var name: String
    var isOn: Bool
    var entity: LightEntity?
}

@available(iOS 18.0, *)
struct LightToggleProvider: AppIntentControlValueProvider {
    func previewValue(configuration: LightControlConfig) -> LightControlValue {
        LightControlValue(name: configuration.light?.name ?? "All lights", isOn: true, entity: configuration.light)
    }

    func currentValue(configuration: LightControlConfig) async throws -> LightControlValue {
        let snaps = LightStore.snaps()
        let e = configuration.light
        if let e, !e.isAll {
            let s = snaps.first { $0.id == e.id }
            return LightControlValue(name: s?.name ?? e.name, isOn: s?.isOn ?? false, entity: e)
        }
        return LightControlValue(name: "All lights", isOn: snaps.contains(where: \.isOn), entity: e)
    }
}

@available(iOS 18.0, *)
struct LightToggleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.afterglow.light", provider: LightToggleProvider()) { value in
            ControlWidgetToggle(value.name, isOn: value.isOn, action: LightSwitchIntent(light: value.entity)) { on in
                Label(on ? "On" : "Off", systemImage: on ? "lightbulb.fill" : "lightbulb")
            }
            .tint(.orange)
        }
        .displayName("Light")
        .description("Turn a light, or all lights, on and off.")
    }
}

struct SceneControlValue {
    var name: String
    var icon: String
    var entity: SceneEntity?
}

@available(iOS 18.0, *)
struct SceneButtonProvider: AppIntentControlValueProvider {
    func previewValue(configuration: SceneControlConfig) -> SceneControlValue {
        SceneControlValue(name: configuration.scene?.name ?? "Scene", icon: configuration.scene?.icon ?? "sparkles", entity: configuration.scene)
    }

    func currentValue(configuration: SceneControlConfig) async throws -> SceneControlValue {
        if let e = configuration.scene, let s = SceneStore.load().first(where: { $0.id == e.id }) {
            return SceneControlValue(name: s.name, icon: s.icon, entity: SceneEntity(s))
        }
        return SceneControlValue(name: configuration.scene?.name ?? "Pick a scene", icon: "sparkles", entity: configuration.scene)
    }
}

@available(iOS 18.0, *)
struct SceneButtonControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.soum91.afterglow.scene", provider: SceneButtonProvider()) { value in
            ControlWidgetButton(action: SceneButtonIntent(scene: value.entity)) {
                Label(value.name, systemImage: value.icon)
            }
            .tint(.orange)
        }
        .displayName("Scene")
        .description("Run one of your Afterglow scenes.")
    }
}
