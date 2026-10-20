import Foundation
import AppIntents

// MARK: - Entities

struct LightEntity: AppEntity, Identifiable {
    static let allID = "__all__"
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Light"
    static var defaultQuery = LightQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    var isAll: Bool { id == Self.allID }

    static let all = LightEntity(id: allID, name: "All lights")
    init(id: String, name: String) { self.id = id; self.name = name }
    init(_ l: Light) { id = l.id; name = l.name }
}

struct LightQuery: EntityStringQuery {
    private func everything() -> [LightEntity] { [.all] + Lights.all().map(LightEntity.init) }

    func entities(for identifiers: [String]) async throws -> [LightEntity] {
        everything().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [LightEntity] {
        let q = string.lowercased()
        return everything().filter { $0.name.lowercased().contains(q) }
    }
    func suggestedEntities() async throws -> [LightEntity] { everything() }
}

struct SceneEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static var defaultQuery = SceneQuery()

    var id: String
    var name: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: icon))
    }
    init(id: String, name: String, icon: String) { self.id = id; self.name = name; self.icon = icon }
    init(_ s: LightScene) { id = s.id; name = s.name; icon = s.icon }
}

struct SceneQuery: EntityStringQuery {
    private func everything() -> [SceneEntity] { SceneStore.load().map(SceneEntity.init) }
    func entities(for identifiers: [String]) async throws -> [SceneEntity] {
        everything().filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [SceneEntity] {
        let q = string.lowercased()
        return everything().filter { $0.name.lowercased().contains(q) }
    }
    func suggestedEntities() async throws -> [SceneEntity] { everything() }
}

// MARK: - Intents

struct AllLightsOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn All Lights Off"
    static var description = IntentDescription("Turns every light in Afterglow off.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await Lights.set(nil, on: false)
        return .result(dialog: "Lights off.")
    }
}

struct AllLightsOnIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn All Lights On"
    static var description = IntentDescription("Turns every light in Afterglow on.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await Lights.set(nil, on: true)
        return .result(dialog: "Lights on.")
    }
}

struct ToggleLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Light"
    static var description = IntentDescription("Turns a light, or all lights, on or off.")

    @Parameter(title: "Light")
    var light: LightEntity

    init() {}
    init(light: LightEntity) { self.light = light }

    static var parameterSummary: some ParameterSummary { Summary("Toggle \(\.$light)") }

    func perform() async throws -> some IntentResult {
        _ = try await Lights.toggle(light.isAll ? nil : light.id)
        return .result()
    }
}

struct SetLightPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Light Power"
    static var description = IntentDescription("Turns a light, or all lights, on or off.")

    @Parameter(title: "Light")
    var light: LightEntity

    @Parameter(title: "On")
    var on: Bool

    init() {}
    init(light: LightEntity, on: Bool) { self.light = light; self.on = on }

    static var parameterSummary: some ParameterSummary { Summary("Turn \(\.$light) \(\.$on)") }

    func perform() async throws -> some IntentResult {
        try await Lights.set(light.isAll ? nil : [light.id], on: on)
        return .result()
    }
}

struct SetBrightnessIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Light Brightness"
    static var description = IntentDescription("Sets a light, or all lights, to a brightness and turns it on.")

    @Parameter(title: "Light")
    var light: LightEntity

    @Parameter(title: "Brightness", default: 50, inclusiveRange: (1, 100))
    var percent: Int

    static var parameterSummary: some ParameterSummary { Summary("Set \(\.$light) to \(\.$percent)%") }

    func perform() async throws -> some IntentResult {
        try await Lights.setBrightness(light.isAll ? nil : light.id, percent: percent)
        return .result()
    }
}

struct RunSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Light Scene"
    static var description = IntentDescription("Runs one of your Afterglow scenes.")

    @Parameter(title: "Scene")
    var scene: SceneEntity

    init() {}
    init(scene: SceneEntity) { self.scene = scene }

    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$scene)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = SceneStore.load().first(where: { $0.id == scene.id }) else {
            throw TuyaError(message: "That scene doesn't exist anymore.")
        }
        try await SceneEngine.run(s)
        return .result(dialog: "\(s.name) is on.")
    }
}

struct GetTVPowerIntent: AppIntent {
    static var title: LocalizedStringResource = "Is the TV On"
    static var description = IntentDescription("Asks the Sony TV whether it's on. Returns true or false.")

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        guard TVConfig.stored.isSet else { throw TuyaError(message: "Set the TV's IP address in Afterglow first.") }
        return .result(value: await TV.power().isOn)
    }
}

/// For Shortcuts automations (time of day, charger, Sleep focus): only acts if the TV is off.
struct LightsOffIfTVOffIntent: AppIntent {
    static var title: LocalizedStringResource = "Lights Off If TV Is Off"
    static var description = IntentDescription("Turns all lights off, unless the Sony TV is on. Good for bedtime automations.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        if TVConfig.stored.isSet, await TV.power().isOn {
            return .result(dialog: "TV is on, leaving the lights.")
        }
        try await Lights.set(nil, on: false)
        return .result(dialog: "Lights off.")
    }
}

/// Pulls fresh light state (used by the widget's refresh and Shortcuts).
struct RefreshLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Lights"
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await Lights.refresh()
        Lights.reloadWidgets()
        return .result()
    }
}

// MARK: - Control Center (iOS 18)

@available(iOS 18.0, *)
struct LightControlConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Light"

    @Parameter(title: "Light")
    var light: LightEntity?

    init() {}
}

@available(iOS 18.0, *)
struct SceneControlConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Scene"

    @Parameter(title: "Scene")
    var scene: SceneEntity?

    init() {}
}

/// The action behind a Control Center toggle.
@available(iOS 18.0, *)
struct LightSwitchIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Switch Light"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Light")
    var light: LightEntity?

    @Parameter(title: "On")
    var value: Bool

    init() {}
    init(light: LightEntity?) { self.light = light }

    func perform() async throws -> some IntentResult {
        let id = light.flatMap { $0.isAll ? nil : $0.id }
        try await Lights.set(id.map { [$0] }, on: value)
        return .result()
    }
}

/// Run-scene button for Control Center. Separate from RunSceneIntent so the scene can be optional.
@available(iOS 18.0, *)
struct SceneButtonIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Scene"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Scene")
    var scene: SceneEntity?

    init() {}
    init(scene: SceneEntity?) { self.scene = scene }

    func perform() async throws -> some IntentResult {
        guard let id = scene?.id, let s = SceneStore.load().first(where: { $0.id == id }) else {
            throw TuyaError(message: "Pick a scene for this control.")
        }
        try await SceneEngine.run(s)
        return .result()
    }
}

// MARK: - Learning

/// Tells Siri when you switch lights off, so it can suggest "Lights Off" at your usual time
/// (lock screen, Spotlight, Siri Suggestions widget).
enum Donate {
    static func lightsOff() {
        Task { _ = try? await IntentDonationManager.shared.donate(intent: AllLightsOffIntent()) }
    }
    static func lightsOn() {
        Task { _ = try? await IntentDonationManager.shared.donate(intent: AllLightsOnIntent()) }
    }
    static func scene(_ s: LightScene) {
        Task { _ = try? await IntentDonationManager.shared.donate(intent: RunSceneIntent(scene: SceneEntity(s))) }
    }
}
