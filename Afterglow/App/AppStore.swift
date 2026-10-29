import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()
    static let refreshID = "com.soum91.afterglow.refresh"

    @Published var token: TuyaToken? = TokenStore.load()
    @Published var lights: [Light] = LightStore.load()
    @Published var scenes: [LightScene] = SceneStore.load()
    @Published var routes: [String: Route] = [:]
    @Published var error: String?
    @Published var loading = false
    @Published var toast: String?
    @Published var finding: String?
    @Published var tvPower: TVPower?
    /// Switches and plugs on the account that aren't shown as lights (yet). Filled by reloadDevices.
    @Published var addable: [DeviceInfo] = []

    private var pollTask: Task<Void, Never>?
    private var pending: [String: LightState] = [:]
    private var sending: Set<String> = []
    private var toastTask: Task<Void, Never>?

    init() {
        LightControl.onStatus = { id, status in
            Task { @MainActor in AppStore.shared.received(id, status) }
        }
    }

    var visible: [Light] { lights.filter { !$0.hidden } }
    var anyOn: Bool { visible.contains { $0.isOn } }

    // MARK: Account

    func signedIn(_ t: TuyaToken) async {
        TokenStore.save(t)
        token = t
        await reloadDevices()
    }

    func signOut() {
        TokenStore.clear()
        token = nil
        Task { await LightControl.shared.dropAll() }
    }

    // MARK: Devices

    func reloadDevices() async {
        guard let t = token ?? TokenStore.load() else { return }
        loading = true
        defer { loading = false }
        let client = TuyaClient(token: t)
        do {
            let all = try await client.allDevices()
            let found = all.filter(\.isLight)
            addable = all.filter { !$0.isLight && $0.isSwitchLike }.sorted { $0.name < $1.name }
            var list = LightStore.load()
            var newOnes: [Light] = []
            for info in found {
                if let i = list.firstIndex(where: { $0.id == info.id }) {
                    let key = list[i].info.localKey
                    list[i].info = info
                    if info.localKey == nil { list[i].info.localKey = key }
                } else {
                    newOnes.append(Light(info: info, order: list.count + newOnes.count))
                }
            }
            // Specs and data point maps for anything we haven't described yet.
            let needSpec = (list + newOnes).filter { $0.functions.isEmpty || $0.dpMap.isEmpty }.map(\.id)
            let specs = await withTaskGroup(of: (String, [String: DPSpec], [String: DPSpec], [String: String]).self) { group in
                for id in needSpec {
                    group.addTask {
                        let spec = try? await client.specification(id: id)
                        let map = (try? await client.dpMap(id: id)) ?? [:]
                        return (id, spec?.functions ?? [:], spec?.status ?? [:], map)
                    }
                }
                var out: [String: ([String: DPSpec], [String: DPSpec], [String: String])] = [:]
                for await r in group { out[r.0] = (r.1, r.2, r.3) }
                return out
            }
            list += newOnes
            for i in list.indices {
                if let s = specs[list[i].id] {
                    if !s.0.isEmpty { list[i].functions = s.0 }
                    if !s.1.isEmpty { list[i].statusSpec = s.1 }
                    if !s.2.isEmpty { list[i].dpMap = s.2 }
                }
            }
            // Lights removed from Smart Life go away here too.
            list.removeAll { l in !found.contains { $0.id == l.id } }
            LightStore.save(list)
            lights = LightStore.load()
            Lights.reloadWidgets()
            AfterglowShortcuts.updateAppShortcutParameters()
            if lights.contains(where: { !$0.hasLocal }) && LocalScan.wifiAddress() != nil && finding == nil {
                Task { await findOnWiFi(quiet: true) }
            }
        } catch let e as TuyaError where e.isAuth {
            error = e.message
            signOut()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Show a switch or plug as a light (or stop showing it).
    func include(_ id: String, _ on: Bool) async {
        var set = DeviceInfo.included
        if on { set.insert(id) } else { set.remove(id) }
        DeviceInfo.included = set
        await reloadDevices()
        show(on ? "Added. Send your lights to the bridge again to put it in Apple Home." : "Removed.")
    }

    // MARK: Polling

    func startPolling() {
        pollTask?.cancel()
        Task { await LightControl.shared.setIdle(45) }
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.poll(cloud: tick % 5 == 0)
                tick += 1
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
        Task { await refreshTV() }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        Task {
            await LightControl.shared.setIdle(8)
            await LightControl.shared.dropAll()
        }
    }

    private func poll(cloud: Bool) async {
        var missing: [String] = []
        for l in visible {
            if sending.contains(l.id) || pending[l.id] != nil { continue }
            if let st = await LightControl.shared.localStatus(l) {
                merge(l.id, st, online: true)
                routes[l.id] = .local
            } else {
                missing.append(l.id)
            }
        }
        guard cloud, !missing.isEmpty, let t = token else { return }
        if let infos = try? await TuyaClient(token: t).devices(ids: missing) {
            for info in infos where !sending.contains(info.id) && pending[info.id] == nil {
                merge(info.id, info.status, online: info.online)
                if routes[info.id] == nil || routes[info.id] == .local { routes[info.id] = .cloud }
            }
        }
    }

    private func received(_ id: String, _ status: [String: JSONValue]) {
        guard !sending.contains(id), pending[id] == nil else { return }
        merge(id, status, online: true)
    }

    private func merge(_ id: String, _ status: [String: JSONValue], online: Bool) {
        guard let i = lights.firstIndex(where: { $0.id == id }) else { return }
        var l = lights[i]
        l.info.status.merge(status) { _, n in n }
        l.info.online = online
        l.updated = .now
        if l != lights[i] {
            lights[i] = l
            LightStore.update(id) { $0.info.status = l.info.status; $0.info.online = online; $0.updated = l.updated }
        }
    }

    // MARK: Control

    /// Optimistic: the UI moves now, the command follows. Slider drags coalesce so a light
    /// only ever has one command in flight and always ends on the last value.
    func set(_ light: Light, _ target: LightState) {
        guard let i = lights.firstIndex(where: { $0.id == light.id }) else { return }
        let before = lights[i]
        let cmds = before.commands(for: target)
        guard !cmds.isEmpty else { return }
        lights[i] = before.applying(cmds)
        pending[light.id] = target
        pump(light.id)
    }

    private func pump(_ id: String) {
        guard !sending.contains(id), let target = pending.removeValue(forKey: id),
              let light = LightStore.load().first(where: { $0.id == id }) else { return }
        sending.insert(id)
        Task {
            do {
                let route = try await LightControl.shared.apply(target, to: light)
                routes[id] = route
            } catch {
                show("\(light.name): \(error.localizedDescription)")
                if let fresh = LightStore.load().first(where: { $0.id == id }), let i = lights.firstIndex(where: { $0.id == id }) {
                    lights[i] = fresh
                }
            }
            sending.remove(id)
            if pending[id] != nil {
                pump(id)
            } else {
                // Reload the stored copy, which includes what the light echoed back.
                if let fresh = LightStore.load().first(where: { $0.id == id }), let i = lights.firstIndex(where: { $0.id == id }) {
                    var merged = lights[i]
                    merged.info.status.merge(fresh.info.status) { _, n in n }
                    lights[i] = merged
                }
                Lights.reloadWidgets()
            }
        }
    }

    func toggle(_ light: Light) {
        set(light, LightState(on: !light.isOn))
        if light.isOn && visible.filter({ $0.isOn }).count == 1 { Donate.lightsOff() }
    }

    func setAll(on: Bool) {
        for l in visible where l.isOn != on && l.powerCode != nil { set(l, LightState(on: on)) }
        if on { Donate.lightsOn() } else { Donate.lightsOff() }
    }

    func run(_ scene: LightScene) async {
        // Optimistic update first, then let the engine send everything in parallel.
        for (l, t) in scene.targets(lights) {
            if let i = lights.firstIndex(where: { $0.id == l.id }) { lights[i] = lights[i].applying(l.commands(for: t)) }
        }
        do {
            try await SceneEngine.run(scene)
            Donate.scene(scene)
        } catch {
            show(error.localizedDescription)
        }
        lights = mergedWithStore()
        scenes = SceneStore.load()
    }

    private func mergedWithStore() -> [Light] {
        let stored = LightStore.load()
        return lights.map { l in
            guard let s = stored.first(where: { $0.id == l.id }) else { return l }
            var m = l
            m.info.status.merge(s.info.status) { _, n in n }
            return m
        }
    }

    // MARK: Editing

    func saveLights(_ list: [Light]) {
        var ordered = list
        for i in ordered.indices { ordered[i].order = i }
        LightStore.save(ordered)
        lights = LightStore.load()
        Lights.reloadWidgets()
        AfterglowShortcuts.updateAppShortcutParameters()
    }

    func updateLight(_ id: String, _ change: (inout Light) -> Void) {
        LightStore.update(id, change)
        lights = LightStore.load()
        Task { await LightControl.shared.drop(id) }
    }

    func saveScene(_ s: LightScene) {
        var list = SceneStore.load()
        if let i = list.firstIndex(where: { $0.id == s.id }) { list[i] = s } else { list.append(s) }
        SceneStore.save(list)
        scenes = list
        Geo.shared.sync()
        Lights.reloadWidgets()
        AfterglowShortcuts.updateAppShortcutParameters()
    }

    func deleteScene(_ s: LightScene) {
        var list = SceneStore.load()
        list.removeAll { $0.id == s.id }
        SceneStore.save(list)
        scenes = list
        Geo.shared.sync()
        AfterglowShortcuts.updateAppShortcutParameters()
    }

    func moveScenes(_ list: [LightScene]) {
        SceneStore.save(list)
        scenes = list
    }

    // MARK: TV

    func refreshTV() async {
        guard TVConfig.stored.isSet else { tvPower = nil; return }
        tvPower = await TV.power()
    }

    // MARK: Messages

    func show(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { toast = nil }
        }
    }
}
