import Foundation

/// A one-tap look for some or all lights, like Equinox's scenes: chips on the home screen,
/// tap to run, long-press to edit, optional arrive/leave trigger.
struct LightScene: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var name: String
    var icon: String = "sparkles"
    /// Light id -> target. Lights not listed are left alone.
    var states: [String: LightState] = [:]
    /// "All visible lights" scenes apply `allState` to every light, including ones added later.
    var allState: LightState? = nil
    var onArrive: Bool? = nil
    var onLeave: Bool? = nil
    var lastRun: Date? = nil

    var hasLocationTrigger: Bool { onArrive == true || onLeave == true }

    func targets(_ lights: [Light]) -> [(Light, LightState)] {
        if let all = allState { return lights.filter { !$0.hidden }.map { ($0, all) } }
        return lights.compactMap { l in states[l.id].map { (l, $0) } }
    }

    func summary(_ lights: [Light]) -> String {
        if let all = allState { return "All lights · \(all.summary)" }
        let n = lights.filter { states[$0.id] != nil }.count
        if n == 0 { return "No lights" }
        let ons = states.values.filter(\.on).count
        if ons == 0 { return "\(n) light\(n == 1 ? "" : "s") off" }
        return "\(n) light\(n == 1 ? "" : "s")"
    }

    static let defaults: [LightScene] = [
        LightScene(name: "Bright", icon: "sun.max.fill", allState: LightState(on: true, brightness: 1, temperature: 0.55)),
        LightScene(name: "Evening", icon: "sunset.fill", allState: LightState(on: true, brightness: 0.55, temperature: 0.12)),
        LightScene(name: "Movie", icon: "tv.fill", allState: LightState(on: true, brightness: 0.12, temperature: 0)),
        LightScene(name: "All off", icon: "moon.zzz.fill", allState: LightState(on: false), onLeave: true),
    ]
}

enum SceneStore {
    private static let file = "scenes.json"
    static func load() -> [LightScene] {
        if let list = AppGroup.read([LightScene].self, file) { return list }
        return LightScene.defaults
    }
    static func save(_ list: [LightScene]) { AppGroup.write(list, file) }
}

enum SceneEngine {
    /// Runs every light in the scene at once, local where possible. Throws only if every light failed.
    static func run(_ scene: LightScene) async throws {
        let targets = scene.targets(LightStore.load())
        guard !targets.isEmpty else { throw TuyaError(message: "\(scene.name) has no lights in it.") }
        let errors = await LightControl.shared.apply(targets)
        var list = SceneStore.load()
        if let i = list.firstIndex(where: { $0.id == scene.id }) {
            list[i].lastRun = .now
            SceneStore.save(list)
        }
        Lights.reloadWidgets()
        if errors.count == targets.count, let e = errors.values.first { throw e }
        if !errors.isEmpty {
            let names = targets.filter { errors[$0.0.id] != nil }.map(\.0.name).joined(separator: ", ")
            throw TuyaError(message: "\(scene.name) ran, but \(names) didn't respond.")
        }
    }
}
