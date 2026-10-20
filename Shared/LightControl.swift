import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum Route: String, Codable { case local, cloud }

/// Sends commands to lights: straight over Wi-Fi when we know where the light is, otherwise
/// (or if that fails) through Tuya's cloud. Used by the app, the widget, Control Center and Siri.
actor LightControl {
    static let shared = LightControl()

    /// The app sets this to hear status pushes from open local connections.
    nonisolated(unsafe) static var onStatus: (@Sendable (String, [String: JSONValue]) -> Void)?

    private var links: [String: LocalLink] = [:]
    private var closers: [String: Task<Void, Never>] = [:]
    private var lastRoute: [String: Route] = [:]
    /// Lights whose local connection failed recently: go straight to the cloud for a bit.
    private var localCooldown: [String: Date] = [:]
    /// How long an idle local connection stays open. The app keeps it longer for live updates.
    var idleSeconds: Double = 8

    func setIdle(_ s: Double) { idleSeconds = s }
    func route(_ id: String) -> Route? { lastRoute[id] }

    // MARK: Commands

    /// Takes a light to `target`. Returns how it got there.
    @discardableResult
    func apply(_ target: LightState, to light: Light, force: Bool = false) async throws -> Route {
        let cmds = light.commands(for: target, force: force)
        guard !cmds.isEmpty else { return lastRoute[light.id] ?? .local }
        return try await send(cmds, to: light)
    }

    @discardableResult
    func send(_ cmds: [(String, JSONValue)], to light: Light) async throws -> Route {
        var localError: Error?
        if canTryLocal(light), let dps = light.localDPS(cmds) {
            do {
                let link = try await link(for: light)
                let echoed = try await link.setConfirmed(dps)
                touch(light.id)
                lastRoute[light.id] = .local
                var updated = light.applying(cmds)
                if let echoed, !echoed.isEmpty { updated = updated.applying(status: light.cloudStatus(echoed)) }
                save(updated)
                return .local
            } catch {
                localError = error
                await drop(light.id)
                localCooldown[light.id] = Date().addingTimeInterval(60)
            }
        }
        guard let token = TokenStore.load() else {
            throw localError ?? TuyaError(message: "Open Afterglow and sign in first.")
        }
        do {
            try await TuyaClient(token: token).send(id: light.id, cmds)
        } catch {
            if let localError { throw TuyaError(message: "Wi-Fi: \(localError.localizedDescription) Cloud: \(error.localizedDescription)") }
            throw error
        }
        lastRoute[light.id] = .cloud
        save(light.applying(cmds))
        return .cloud
    }

    /// Runs one target per light at the same time.
    func apply(_ targets: [(Light, LightState)], force: Bool = false) async -> [String: Error] {
        await withTaskGroup(of: (String, Error?).self) { group in
            for (light, target) in targets {
                group.addTask {
                    do {
                        try await self.apply(target, to: light, force: force)
                        return (light.id, nil)
                    } catch {
                        return (light.id, error)
                    }
                }
            }
            var errors: [String: Error] = [:]
            for await (id, err) in group { if let err { errors[id] = err } }
            return errors
        }
    }

    // MARK: Status

    /// Fresh status over Wi-Fi, or nil if the light isn't reachable locally.
    func localStatus(_ light: Light) async -> [String: JSONValue]? {
        guard canTryLocal(light) else { return nil }
        do {
            let link = try await link(for: light)
            let dps = try await link.query()
            touch(light.id)
            lastRoute[light.id] = .local
            return light.cloudStatus(dps)
        } catch {
            await drop(light.id)
            localCooldown[light.id] = Date().addingTimeInterval(30)
            return nil
        }
    }

    // MARK: Connections

    private func canTryLocal(_ light: Light) -> Bool {
        guard light.hasLocal, let host = light.host else { return false }
        if let until = localCooldown[light.id], until > Date() { return false }
        // Off home Wi-Fi a LAN address just times out, so don't wait for it.
        guard let me = LocalScan.wifiAddress() else { return false }
        return Self.sameSubnet(me, host)
    }

    static func sameSubnet(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: "."), y = b.split(separator: ".")
        guard x.count == 4, y.count == 4 else { return true }
        return x[0..<3] == y[0..<3]
    }

    private func link(for light: Light) async throws -> LocalLink {
        if let l = links[light.id], await l.isOpen { return l }
        links[light.id] = nil
        guard let host = light.host, let key = light.localKey else { throw LocalError("No local address.") }
        let id = light.id
        let onDPS: @Sendable ([String: JSONValue]) -> Void = { dps in
            Task { await LightControl.shared.pushed(id, dps) }
        }
        let onClose: @Sendable (String) -> Void = { _ in
            Task { await LightControl.shared.forget(id) }
        }
        let known = Array(light.codeMap().keys)
        var link: LocalLink
        if let v = light.version {
            link = LocalLink(devId: id, host: host, localKey: key, version: v, knownDPs: known, timeout: 3, onDPS: onDPS, onClose: onClose)
            do {
                try await link.open()
            } catch {
                await link.close()
                let found = try await LocalLink.detect(devId: id, host: host, localKey: key, knownDPs: known, timeout: 3, onDPS: onDPS, onClose: onClose)
                link = found.0
            }
        } else {
            let found = try await LocalLink.detect(devId: id, host: host, localKey: key, knownDPs: known, timeout: 3, onDPS: onDPS, onClose: onClose)
            link = found.0
        }
        if light.version != link.version {
            let v = link.version
            LightStore.update(id) { $0.version = v }
        }
        links[id] = link
        touch(id)
        return link
    }

    private func touch(_ id: String) {
        closers[id]?.cancel()
        let wait = idleSeconds
        closers[id] = Task {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            if Task.isCancelled { return }
            await self.drop(id)
        }
    }

    func drop(_ id: String) async {
        closers[id]?.cancel()
        closers[id] = nil
        if let l = links.removeValue(forKey: id) { await l.close() }
    }

    func dropAll() async {
        for id in Array(links.keys) { await drop(id) }
    }

    private func forget(_ id: String) {
        links[id] = nil
        closers[id]?.cancel()
        closers[id] = nil
    }

    private func pushed(_ id: String, _ dps: [String: JSONValue]) {
        guard let light = LightStore.load().first(where: { $0.id == id }) else { return }
        let status = light.cloudStatus(dps)
        guard !status.isEmpty else { return }
        save(light.applying(status: status))
        Self.onStatus?(id, status)
    }

    private func save(_ light: Light) {
        var list = LightStore.load()
        if let i = list.firstIndex(where: { $0.id == light.id }) {
            list[i].info.status.merge(light.info.status) { _, new in new }
            list[i].updated = light.updated
            LightStore.save(list)
        }
    }
}

extension Light {
    func applying(status: [String: JSONValue]) -> Light {
        applying(status.map { ($0.key, $0.value) })
    }
}

/// Entry points for code outside the app's UI (widget, Control Center, Siri, background).
enum Lights {
    static func all() -> [Light] { LightStore.visible() }
    static func find(_ id: String) -> Light? { LightStore.load().first { $0.id == id } }

    static func set(_ ids: [String]?, on: Bool) async throws {
        let pool = all()
        let targets = (ids.map { wanted in pool.filter { wanted.contains($0.id) } } ?? pool).filter { $0.powerCode != nil }
        guard !targets.isEmpty else { throw TuyaError(message: "No lights found. Open Afterglow first.") }
        let errors = await LightControl.shared.apply(targets.map { ($0, LightState(on: on)) }, force: true)
        reloadWidgets()
        if errors.count == targets.count, let e = errors.values.first { throw e }
    }

    static func toggle(_ id: String?) async throws -> Bool {
        if let id, let l = find(id) {
            let on = !l.isOn
            try await LightControl.shared.apply(LightState(on: on), to: l, force: true)
            reloadWidgets()
            return on
        }
        let anyOn = all().contains { $0.isOn }
        try await set(nil, on: !anyOn)
        return !anyOn
    }

    static func setBrightness(_ id: String?, percent: Int) async throws {
        let p = Double(max(1, min(100, percent))) / 100
        let targets = (id.flatMap { find($0) }.map { [$0] } ?? all()).filter(\.canDim)
        guard !targets.isEmpty else { throw TuyaError(message: "That light can't dim.") }
        let errors = await LightControl.shared.apply(targets.map { ($0, LightState(on: true, brightness: p)) })
        reloadWidgets()
        if errors.count == targets.count, let e = errors.values.first { throw e }
    }

    /// Pulls fresh state for widgets: local first, then one cloud call for everything else.
    static func refresh() async {
        var list = LightStore.load()
        var missing: [String] = []
        for i in list.indices where !list[i].hidden {
            if let st = await LightControl.shared.localStatus(list[i]) {
                list[i].info.status.merge(st) { _, n in n }
                list[i].info.online = true
                list[i].updated = .now
            } else {
                missing.append(list[i].id)
            }
        }
        if !missing.isEmpty, let token = TokenStore.load() {
            let client = TuyaClient(token: token)
            if let infos = try? await client.devices(ids: missing) {
                for info in infos {
                    if let i = list.firstIndex(where: { $0.id == info.id }) {
                        let key = list[i].info.localKey
                        list[i].info = info
                        if info.localKey == nil { list[i].info.localKey = key }
                        list[i].updated = .now
                    }
                }
            }
        }
        // Merge onto whatever changed meanwhile.
        var latest = LightStore.load()
        for l in list {
            if let i = latest.firstIndex(where: { $0.id == l.id }) {
                latest[i].info.status.merge(l.info.status) { _, n in n }
                latest[i].info.online = l.info.online
                latest[i].updated = l.updated
            }
        }
        LightStore.save(latest)
    }

    static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        #endif
    }
}
