import Foundation
import Network

/// What the TV automations should do. Stored in the app and pushed to the ESP32 bridge,
/// which is what actually runs them (it's always on; the phone isn't).
struct Automations: Codable, Equatable {
    var tvOffEnabled = true
    /// Scene to run when the TV turns off. Nil means "all lights off".
    var tvOffScene: String? = nil
    /// -1 = learn it from you, otherwise seconds.
    var tvOffDelay: Int = -1
    var tvOffWindow = true
    var tvOffFrom = 19 * 60      // minutes after midnight
    var tvOffTo = 6 * 60

    var tvOnEnabled = false
    var tvOnScene: String? = nil
    var tvOnWindow = true
    var tvOnFrom = 18 * 60
    var tvOnTo = 2 * 60

    var lateOffEnabled = false
    var lateOffAt = 2 * 60 + 30

    static var stored: Automations {
        get { AppGroup.read(Automations.self, "automations.json") ?? Automations() }
        set { AppGroup.write(newValue, "automations.json") }
    }
}

struct BridgeConfig: Codable, Equatable {
    var host: String = ""
    var port: Int = 8080
    var token: String = ""
    var lastPush: Date?

    var isSet: Bool { !host.isEmpty }

    static var stored: BridgeConfig {
        get { AppGroup.read(BridgeConfig.self, "bridge.json") ?? BridgeConfig() }
        set { AppGroup.write(newValue, "bridge.json") }
    }
}

/// What the bridge reports back.
struct BridgeInfo: Decodable {
    struct L: Decodable, Identifiable { var id: String; var name: String; var on: Bool?; var bri: Int?; var ok: Bool? }
    struct T: Decodable { var state: String?; var host: String? }
    var app: String
    var version: String?
    var claimed: Bool?
    var lights: [L]?
    var tv: T?
    var learnedDelay: Int?
    var samples: Int?
    var events: [String]?
    var uptime: Int?
    var time: String?
    var build: Int?
    var chip: String?
    var purifier: Purifier?
    var ir: IR?
    var govee: Govee?
    var tvTile: TVTile?

    struct Purifier: Decodable { var paired: Bool?; var configured: Bool?; var name: String?; var ok: Bool?; var on: Bool?; var pm25: Double?; var speed: Int? }
    struct IR: Decodable { struct R: Decodable { var name: String; var buttons: Int? }; var paired: Bool?; var remotes: [R]? }
    struct Govee: Decodable { var locked: Bool?; var name: String?; var temp: Double?; var humidity: Double?; var battery: Int? }
    struct TVTile: Decodable { var inHome: Bool?; var inputs: [String]? }
}

enum BridgeError: LocalizedError {
    case message(String)
    case rejected
    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        case .rejected: return "The bridge forgot Afterglow's pairing and Keystone holds it now. In Keystone › Bridge › Pairings, tap Reset next to Afterglow, then try again here."
        }
    }
}

extension BridgeAPI {
    /// The bridge forgot this phone (another app cleared Afterglow's slot). If the slot is free, take it again.
    static func reclaim() async -> Bool {
        var cfg = BridgeConfig.stored
        guard cfg.isSet, let t = try? await claim(cfg) else { return false }
        cfg.token = t
        BridgeConfig.stored = cfg
        return true
    }

    /// Runs `work`, re-pairing once if the bridge says it doesn't know this phone.
    static func withRepair<T>(_ work: (BridgeConfig) async throws -> T) async throws -> T {
        do {
            return try await work(.stored)
        } catch BridgeError.rejected {
            guard await reclaim() else { throw BridgeError.rejected }
            return try await work(.stored)
        }
    }
}

enum BridgeAPI {
    static func url(_ cfg: BridgeConfig, _ path: String) -> URL? {
        URL(string: "http://\(cfg.host):\(cfg.port)\(path)")
    }

    static func info(_ cfg: BridgeConfig = .stored) async throws -> BridgeInfo {
        guard let u = url(cfg, "/api/info") else { throw BridgeError.message("Bad bridge address.") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 4
        let (data, _) = try await URLSession.shared.data(for: req)
        let info = try JSONDecoder().decode(BridgeInfo.self, from: data)
        guard info.app == "afterglow-bridge" else { throw BridgeError.message("That isn't a Keystone Bridge.") }
        return info
    }

    /// First app to talk to a fresh bridge gets its token. Reset with @R on the serial console.
    static func claim(_ cfg: BridgeConfig) async throws -> String {
        guard let u = url(cfg, "/api/claim") else { throw BridgeError.message("Bad bridge address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 409 {
            throw BridgeError.message("This bridge already belongs to another phone. Type @R in its serial console to reset it.")
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any], let t = obj["token"] as? String else {
            throw BridgeError.message("The bridge didn't hand out a token.")
        }
        return t
    }

    static func push(_ body: [String: Any], _ cfg: BridgeConfig) async throws -> Bool {
        guard let u = url(cfg, "/api/config") else { throw BridgeError.message("Bad bridge address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(cfg.token, forHTTPHeaderField: "X-Afterglow-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw BridgeError.rejected }
        guard code == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.message("Bridge said: \(String(decoding: data, as: UTF8.self))")
        }
        return obj["restart"] as? Bool ?? false
    }

    // MARK: Building the config

    /// Everything the bridge needs, already in local data point form so the firmware doesn't need to know Tuya codes.
    static func config(lights: [Light], scenes: [LightScene], auto: Automations, tv: TVConfig) -> [String: Any] {
        let usable = lights.filter { $0.hasLocal && !$0.hidden }
        var ls: [[String: Any]] = []
        for l in usable {
            var d: [String: Any] = ["id": l.id, "name": l.name, "key": l.localKey ?? "", "ip": l.host ?? "", "ver": l.version ?? 3.3]
            if let c = l.powerCode, let dp = l.dpID(for: c) { d["sw"] = dp }
            if let c = l.modeCode, let dp = l.dpID(for: c) { d["mode"] = dp }
            if let c = l.brightCode, let dp = l.dpID(for: c) {
                d["bri"] = dp; d["briMin"] = Int(l.brightRange.lowerBound); d["briMax"] = Int(l.brightRange.upperBound)
            }
            if let c = l.tempCode, let dp = l.dpID(for: c) {
                d["ct"] = dp; d["ctMin"] = Int(l.tempRange.lowerBound); d["ctMax"] = Int(l.tempRange.upperBound)
            }
            if let c = l.colourCode, let dp = l.dpID(for: c) { d["col"] = dp; d["colV1"] = l.isV1 || c == "colour_data" }
            if d["sw"] != nil { ls.append(d) }
        }
        func actions(_ sceneID: String?, fallbackOff: Bool) -> [[String: Any]] {
            let scene = sceneID.flatMap { id in scenes.first { $0.id == id } }
            let targets: [(Light, LightState)] = scene?.targets(usable) ?? (fallbackOff ? usable.map { ($0, LightState(on: false)) } : [])
            return targets.compactMap { l, t in
                guard let dps = l.localDPS(l.commands(for: t, force: true)), !dps.isEmpty else { return nil }
                return ["id": l.id, "dps": dps.mapValues { $0.any }]
            }
        }
        return [
            "utcOffset": TimeZone.current.secondsFromGMT(),
            "lights": ls,
            "tv": ["ip": tv.host, "psk": tv.psk, "name": tv.name.isEmpty ? "TV" : tv.name,
                   "inputs": (tv.inputs ?? []).map { ["uri": $0.uri, "name": $0.name] }],
            "tvOff": ["enabled": auto.tvOffEnabled && tv.isSet, "delay": auto.tvOffDelay, "window": auto.tvOffWindow,
                      "from": auto.tvOffFrom, "to": auto.tvOffTo, "actions": actions(auto.tvOffScene, fallbackOff: true)],
            "tvOn": ["enabled": auto.tvOnEnabled && tv.isSet && auto.tvOnScene != nil, "window": auto.tvOnWindow,
                     "from": auto.tvOnFrom, "to": auto.tvOnTo, "actions": actions(auto.tvOnScene, fallbackOff: false)],
            "lateOff": ["enabled": auto.lateOffEnabled, "at": auto.lateOffAt],
        ]
    }
}

/// Finds the bridge by its Bonjour service (_afterglow._tcp).
@MainActor
final class BridgeFinder: ObservableObject {
    @Published var found: [(name: String, host: String, port: Int)] = []
    @Published var searching = false
    private var browser: NWBrowser?

    func start() {
        stop()
        searching = true
        found = []
        let b = NWBrowser(for: .bonjour(type: "_afterglow._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            for r in results {
                guard case .service(let name, _, _, _) = r.endpoint else { continue }
                Task { await self?.resolve(r.endpoint, name: name) }
            }
        }
        b.start(queue: .main)
        browser = b
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            searching = false
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        searching = false
    }

    /// Opens a throwaway connection to learn the service's IP and port.
    private func resolve(_ endpoint: NWEndpoint, name: String) async {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options { ip.version = .v4 }
        let c = NWConnection(to: endpoint, using: params)
        let result: (String, Int)? = await withCheckedContinuation { cont in
            let once = OnceFlag()
            c.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let h, let p)? = c.currentPath?.remoteEndpoint, once.fire() {
                        var host = "\(h)"
                        if let pct = host.firstIndex(of: "%") { host = String(host[..<pct]) }
                        cont.resume(returning: (host, Int(p.rawValue)))
                    } else if once.fire() { cont.resume(returning: nil) }
                    c.cancel()
                case .failed, .cancelled:
                    if once.fire() { cont.resume(returning: nil) }
                default: break
                }
            }
            c.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 4) {
                if once.fire() { cont.resume(returning: nil); c.cancel() }
            }
        }
        guard let r = result, !found.contains(where: { $0.host == r.0 }) else { return }
        found.append((name, r.0, r.1))
    }
}

enum BridgeSync {
    private static let hashKey = "bridge.lastConfig"

    static func currentConfig() -> [String: Any] {
        BridgeAPI.config(lights: LightStore.load(), scenes: SceneStore.load(), auto: .stored, tv: .stored)
    }

    static func fingerprint(_ body: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Sends the config if anything changed since the last push (lights, keys, IPs, scenes, rules, time zone).
    @discardableResult
    static func pushIfChanged(force: Bool = false) async -> String? {
        var cfg = BridgeConfig.stored
        guard cfg.isSet, !cfg.token.isEmpty else { return nil }
        let body = currentConfig()
        let fp = fingerprint(body)
        if !force, UserDefaults.standard.string(forKey: hashKey) == fp { return nil }
        do {
            let restart = try await BridgeAPI.withRepair { c in try await BridgeAPI.push(body, c) }
            UserDefaults.standard.set(fp, forKey: hashKey)
            cfg = BridgeConfig.stored
            cfg.lastPush = .now
            BridgeConfig.stored = cfg
            return restart ? "Sent. The bridge is restarting to update Apple Home (about 20 s)." : "Sent to the bridge."
        } catch {
            return "Couldn't reach the bridge: \(error.localizedDescription)"
        }
    }
}

extension BridgeAPI {
    /// Clears Exhale's or Redshift's pairing so it can pair again (after a reinstall).
    static func resetDevicePairing(_ app: String, _ cfg: BridgeConfig = .stored) async throws {
        guard let u = url(cfg, "/api/dev/reset?app=\(app)") else { throw BridgeError.message("Bad bridge address.") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 5
        req.setValue(cfg.token, forHTTPHeaderField: "X-Afterglow-Token")
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            guard cfg == BridgeConfig.stored, await reclaim() else { throw BridgeError.rejected }
            return try await resetDevicePairing(app, .stored)
        }
        guard code == 200 else { throw BridgeError.message("The bridge refused. Update its firmware first.") }
    }
}

/// Bridge firmware updates over Wi-Fi: the phone fetches the right .bin from GitHub and uploads it.
enum BridgeFirmware {
    struct Latest { var build: Int; var url: URL }

    static func latest(chip: String) async throws -> Latest? {
        let api = URL(string: "https://api.github.com/repos/soum91/keystone/releases/tags/firmware-latest")!
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = obj["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            guard let name = a["name"] as? String, name.hasSuffix("-app.bin"),
                  let prefix = ["KeystoneBridge-\(chip)-build-", "AfterglowBridge-\(chip)-build-"].first(where: { name.hasPrefix($0) }),
                  let n = Int(name.dropFirst(prefix.count).dropLast("-app.bin".count)),
                  let s = a["browser_download_url"] as? String, let u = URL(string: s) else { continue }
            return Latest(build: n, url: u)
        }
        return nil
    }

    static func install(_ latest: Latest, cfg: BridgeConfig = .stored, progress: @escaping (String) -> Void) async throws {
        progress("Downloading build \(latest.build)…")
        let (bin, resp) = try await URLSession.shared.data(from: latest.url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, bin.count > 100_000, bin.first == 0xE9 else {
            throw BridgeError.message("The download didn't look like ESP32 firmware.")
        }
        progress("Sending \(bin.count / 1024) KB to the bridge…")
        guard let u = BridgeAPI.url(cfg, "/api/update") else { throw BridgeError.message("Bad bridge address.") }
        let boundary = "afterglow-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"fw\"; filename=\"fw.bin\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(bin)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(cfg.token, forHTTPHeaderField: "X-Afterglow-Token")
        let (data, r) = try await URLSession.shared.upload(for: req, from: body)
        let code = (r as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { throw BridgeError.rejected }
        guard code == 200 else { throw BridgeError.message("Update failed: \(String(decoding: data, as: UTF8.self))") }
        progress("Installed. The bridge is restarting (about 20 s).")
    }
}
