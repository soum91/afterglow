import Foundation

/// The Sony TV, read over its Bravia REST API (Settings > Network > Home network > IP control).
/// getPowerStatus needs no login on most models; a pre-shared key is sent if you set one.
struct TVConfig: Codable, Equatable {
    var host: String = ""
    var psk: String = ""
    var name: String = "Sony TV"
    /// HDMI and other inputs, read from the TV, for the TV tile in Apple Home.
    var inputs: [TVInput]? = nil

    var isSet: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }

    static var stored: TVConfig {
        get { AppGroup.read(TVConfig.self, "tv.json") ?? TVConfig() }
        set { AppGroup.write(newValue, "tv.json") }
    }
}

struct TVInput: Codable, Equatable, Hashable {
    var uri: String
    var name: String
}

enum TVPower: String, Codable {
    case on, standby, unreachable

    var label: String {
        switch self {
        case .on: return "On"
        case .standby: return "Off (standby)"
        case .unreachable: return "Off (not on the network)"
        }
    }
    var isOn: Bool { self == .on }
}

enum TV {
    static func power(_ cfg: TVConfig = .stored, timeout: Double = 2.5) async -> TVPower {
        let host = cfg.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let url = URL(string: "http://\(host)/sony/system") else { return .unreachable }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.psk.isEmpty { req.setValue(cfg.psk, forHTTPHeaderField: "X-Auth-PSK") }
        req.httpBody = Data(#"{"method":"getPowerStatus","id":50,"params":[],"version":"1.0"}"#.utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unreachable }
        if let result = obj["result"] as? [[String: Any]], let status = result.first?["status"] as? String {
            return status == "active" ? .on : .standby
        }
        // Answered with an error (for example auth): the TV is awake enough to talk, so call it on.
        return obj["error"] != nil ? .on : .unreachable
    }
}

extension TV {
    /// The TV's external inputs (HDMI 1-4 and so on), using your labels when you've renamed them on the TV.
    static func inputs(_ cfg: TVConfig = .stored) async -> [TVInput]? {
        let host = cfg.host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, let url = URL(string: "http://\(host)/sony/avContent") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 4
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !cfg.psk.isEmpty { req.setValue(cfg.psk, forHTTPHeaderField: "X-Auth-PSK") }
        req.httpBody = Data(#"{"method":"getCurrentExternalInputsStatus","id":105,"params":[],"version":"1.1"}"#.utf8)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (obj["result"] as? [Any])?.first as? [[String: Any]] else { return nil }
        let list: [TVInput] = result.compactMap { i in
            guard let uri = i["uri"] as? String else { return nil }
            let label = (i["label"] as? String) ?? ""
            let title = (i["title"] as? String) ?? uri
            return TVInput(uri: uri, name: label.isEmpty ? title : label)
        }
        return list.isEmpty ? nil : Array(list.prefix(12))
    }
}
