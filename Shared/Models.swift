import Foundation

struct DeviceInfo: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var category: String
    var productName: String
    var online: Bool
    var status: [String: JSONValue]
    var localKey: String? = nil

    static func parse(_ d: [String: Any]) -> DeviceInfo? {
        guard let id = d["id"] as? String else { return nil }
        var status: [String: JSONValue] = [:]
        if let list = d["status"] as? [[String: Any]] {
            for item in list {
                if let code = item["code"] as? String { status[code] = JSONValue.from(item["value"]) }
            }
        } else if let dict = d["status"] as? [String: Any] {
            for (k, v) in dict { status[k] = JSONValue.from(v) }
        }
        return DeviceInfo(id: id,
                          name: (d["name"] as? String) ?? "Device",
                          category: (d["category"] as? String) ?? "",
                          productName: (d["product_name"] as? String) ?? (d["productName"] as? String) ?? "",
                          online: (d["online"] as? Bool) ?? ((d["online"] as? NSNumber)?.boolValue ?? true),
                          status: status,
                          localKey: (d["local_key"] as? String) ?? (d["localKey"] as? String))
    }

    /// Tuya light categories: dj bulb, dd strip, xdd ceiling, fwd ambient, dc string, tgq dimmer,
    /// tyndj solar, sxd spotlight, gyd motion light, fsd fan light, mbd/qn misc lamps.
    static let lightCategories: Set<String> = ["dj", "dd", "xdd", "fwd", "dc", "tgq", "tyndj", "sxd", "gyd", "fsd", "mbd", "tgkg"]
    /// Switches and plugs the person added by hand (a light on a smart switch, whatever it's called).
    static var included: Set<String> {
        get { Set(AppGroup.read([String].self, "included-devices.json") ?? []) }
        set { AppGroup.write(Array(newValue), "included-devices.json") }
    }
    /// Things that switch something on and off, which could have a light behind them.
    var isSwitchLike: Bool {
        ["kg", "cz", "pc", "tdq", "kgq", "dlq", "znjdq"].contains(category) ||
            status.keys.contains { $0 == "switch" || $0.hasPrefix("switch_") }
    }
    var isLight: Bool {
        if Self.included.contains(id) { return true }
        if Self.lightCategories.contains(category) { return true }
        // A lamp on a smart plug or switch counts if it's named like one.
        let plugs: Set<String> = ["cz", "pc", "kg", "tdq"]
        let n = name.lowercased()
        if plugs.contains(category) && (n.contains("lamp") || n.contains("light") || n.contains("bulb")) { return true }
        let keys = status.keys
        return keys.contains("switch_led") || keys.contains("bright_value_v2") || keys.contains("bright_value") || keys.contains("colour_data_v2")
    }
}

/// One data point's type and range from the device specification.
struct DPSpec: Codable, Hashable {
    var code: String
    var type: String          // Boolean, Integer, Enum, String, Json, Raw, Bitmap
    var range: [String]?      // Enum
    var min: Double?
    var max: Double?
    var step: Double?
    var scale: Int?
    var unit: String?
    var name: String?

    static func parse(_ d: [String: Any]) -> DPSpec? {
        guard let code = d["code"] as? String else { return nil }
        var s = DPSpec(code: code, type: (d["type"] as? String) ?? "")
        s.name = d["name"] as? String
        var values: [String: Any] = [:]
        if let str = d["values"] as? String, let data = str.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            values = obj
        } else if let obj = d["values"] as? [String: Any] {
            values = obj
        }
        s.range = (values["range"] as? [Any])?.map { "\($0)" }
        s.min = (values["min"] as? NSNumber)?.doubleValue
        s.max = (values["max"] as? NSNumber)?.doubleValue
        s.step = (values["step"] as? NSNumber)?.doubleValue
        s.scale = (values["scale"] as? NSNumber)?.intValue
        s.unit = values["unit"] as? String
        return s
    }

    var isBool: Bool { type.lowercased() == "boolean" || type.lowercased() == "bool" }
    var isEnum: Bool { type.lowercased() == "enum" }
    var isInt: Bool { type.lowercased() == "integer" || type.lowercased() == "value" }
    var divisor: Double { pow(10, Double(scale ?? 0)) }
}

