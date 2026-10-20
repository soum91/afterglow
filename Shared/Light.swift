import Foundation
import SwiftUI

/// One Tuya light: what the cloud told us about it, plus what we learned about reaching it on Wi-Fi.
struct Light: Codable, Identifiable, Hashable {
    var info: DeviceInfo
    var functions: [String: DPSpec] = [:]
    var statusSpec: [String: DPSpec] = [:]
    /// Local data point id -> cloud code.
    var dpMap: [String: String] = [:]
    var host: String?
    var version: Double?
    /// Hidden lights stay out of the grid, widgets and "all lights".
    var hidden: Bool = false
    var order: Int = 0
    /// Last time a status came in, from either path.
    var updated: Date?

    var id: String { info.id }
    var name: String { info.name }
    var status: [String: JSONValue] { info.status }
    var localKey: String? { info.localKey }
    var hasLocal: Bool { !(host ?? "").isEmpty && !(localKey ?? "").isEmpty }

    func spec(_ code: String) -> DPSpec? { functions[code] ?? statusSpec[code] }
    private func first(_ codes: [String]) -> String? {
        codes.first { functions[$0] != nil } ?? codes.first { status[$0] != nil }
    }

    // MARK: Codes

    var powerCode: String? { first(["switch_led", "switch_led_1", "led_switch", "switch_1", "switch"]) }
    var modeCode: String? { first(["work_mode", "work_mode_1"]) }
    var brightCode: String? { first(["bright_value_v2", "bright_value", "bright_value_1", "bright_value_2"]) }
    var tempCode: String? { first(["temp_value_v2", "temp_value", "temp_value_1"]) }
    var colourCode: String? { first(["colour_data_v2", "colour_data", "colour_data_hsv"]) }

    var canDim: Bool { brightCode != nil || colourCode != nil }
    var canTemp: Bool { tempCode != nil }
    var canColour: Bool { colourCode != nil }

    /// Older (v1) firmware: brightness 25...255 and colour s/v 0...255.
    var isV1: Bool {
        if let b = brightCode { return !b.hasSuffix("_v2") && (spec(b)?.max ?? 1000) <= 255 }
        if let c = colourCode { return c == "colour_data" }
        return false
    }

    // MARK: Ranges

    var brightRange: ClosedRange<Double> {
        guard let c = brightCode, let s = spec(c) else { return isV1 ? 25...255 : 10...1000 }
        let lo = s.min ?? (isV1 ? 25 : 10), hi = s.max ?? (isV1 ? 255 : 1000)
        return lo < hi ? lo...hi : (isV1 ? 25...255 : 10...1000)
    }
    var tempRange: ClosedRange<Double> {
        guard let c = tempCode, let s = spec(c) else { return isV1 ? 0...255 : 0...1000 }
        let lo = s.min ?? 0, hi = s.max ?? (isV1 ? 255 : 1000)
        return lo < hi ? lo...hi : (isV1 ? 0...255 : 0...1000)
    }
    var svMax: Double { isV1 ? 255 : 1000 }

    // MARK: State

    var isOn: Bool { powerCode.flatMap { status[$0]?.boolValue } ?? false }
    var online: Bool { info.online }

    var mode: String {
        if let m = modeCode, let v = status[m]?.stringValue { return v }
        return "white"
    }
    var isColourMode: Bool { mode == "colour" && canColour }

    struct HSV: Codable, Hashable { var h: Double; var s: Double; var v: Double }

    /// Colour as 0...360 / 0...1 / 0...1.
    var colour: HSV? {
        guard let c = colourCode, let raw = status[c]?.stringValue else { return nil }
        return Self.parseColour(raw, svMax: svMax)
    }

    static func parseColour(_ raw: String, svMax: Double) -> HSV? {
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            func n(_ k: String) -> Double? { (obj[k] as? NSNumber)?.doubleValue ?? Double("\(obj[k] ?? "")") }
            guard let h = n("h"), let s = n("s"), let v = n("v") else { return nil }
            return HSV(h: h, s: min(1, s / svMax), v: min(1, v / svMax))
        }
        return nil
    }

    /// 0...1 brightness, whichever mode the light is in.
    var brightness: Double {
        if isColourMode, let c = colour { return c.v }
        guard let code = brightCode, let raw = status[code]?.doubleValue else { return isOn ? 1 : 0 }
        let r = brightRange
        return max(0, min(1, (raw - r.lowerBound) / (r.upperBound - r.lowerBound)))
    }

    var percent: Int { max(1, Int((brightness * 100).rounded())) }

    /// 0 warm ... 1 cool.
    var temperature: Double? {
        guard let code = tempCode, let raw = status[code]?.doubleValue else { return nil }
        let r = tempRange
        return max(0, min(1, (raw - r.lowerBound) / (r.upperBound - r.lowerBound)))
    }

    /// What the bulb looks like right now, for tiles and widgets.
    var tint: Color { Self.tint(colourMode: isColourMode, colour: colour, temperature: temperature) }

    static func tint(colourMode: Bool, colour: HSV?, temperature: Double?) -> Color {
        if colourMode, let c = colour { return Color(hue: c.h / 360, saturation: max(0.35, c.s), brightness: 1) }
        return Kelvin.color(temperature ?? 0.25)
    }

    func applying(_ cmds: [(String, JSONValue)]) -> Light {
        var copy = self
        for (k, v) in cmds { copy.info.status[k] = v }
        copy.updated = .now
        return copy
    }
}

enum Kelvin {
    /// Most Tuya white bulbs run 2700 K (0) to 6500 K (1).
    static func kelvin(_ t: Double) -> Int { Int(2700 + t * 3800) }

    static func color(_ t: Double) -> Color {
        let warm = (r: 1.0, g: 0.72, b: 0.38), cool = (r: 0.86, g: 0.92, b: 1.0)
        return Color(red: warm.r + (cool.r - warm.r) * t, green: warm.g + (cool.g - warm.g) * t, blue: warm.b + (cool.b - warm.b) * t)
    }
}

// MARK: - Desired state, used by controls, scenes and the bridge

/// A full or partial target for one light. Nil fields are left as they are.
struct LightState: Codable, Hashable {
    var on: Bool
    var brightness: Double? = nil      // 0...1
    var temperature: Double? = nil     // 0 warm ... 1 cool
    var hue: Double? = nil             // 0...360
    var saturation: Double? = nil      // 0...1

    var isColour: Bool { hue != nil }

    var summary: String {
        guard on else { return "Off" }
        var parts: [String] = []
        if let b = brightness { parts.append("\(max(1, Int((b * 100).rounded())))%") }
        if hue != nil { parts.append("colour") } else if let t = temperature { parts.append("\(Kelvin.kelvin(t)) K") }
        return parts.isEmpty ? "On" : parts.joined(separator: " · ")
    }
}

extension Light {
    /// The current look, for "capture" in the scene editor.
    var currentState: LightState {
        guard isOn else { return LightState(on: false) }
        var s = LightState(on: true, brightness: canDim ? brightness : nil)
        if isColourMode, let c = colour {
            s.hue = c.h
            s.saturation = c.s
        } else if canTemp {
            s.temperature = temperature
        }
        return s
    }

    /// Cloud-style commands (code, value) that take this light to `target`, skipping what already matches.
    func commands(for target: LightState, force: Bool = false) -> [(String, JSONValue)] {
        var out: [(String, JSONValue)] = []
        guard let power = powerCode else { return out }
        if !target.on {
            if force || isOn { out.append((power, .bool(false))) }
            return out
        }
        if force || !isOn { out.append((power, .bool(true))) }

        if let h = target.hue, let code = colourCode {
            let s = target.saturation ?? 1
            let v = target.brightness ?? (isColourMode ? (colour?.v ?? 1) : brightness)
            if let m = modeCode, force || mode != "colour" { out.append((m, .string("colour"))) }
            out.append((code, .string(colourJSON(h: h, s: s, v: v))))
            return out
        }

        let wantWhite = target.temperature != nil || (target.brightness != nil && !isColourMode)
        if wantWhite, let m = modeCode, (force || mode != "white"), target.temperature != nil || brightCode != nil {
            out.append((m, .string("white")))
        }
        if let b = target.brightness {
            if isColourMode && target.temperature == nil, let code = colourCode, let c = colour {
                out.append((code, .string(colourJSON(h: c.h, s: c.s, v: b))))
            } else if let code = brightCode {
                let r = brightRange
                let raw = Int((r.lowerBound + b * (r.upperBound - r.lowerBound)).rounded())
                if force || status[code]?.doubleValue.map({ Int($0) }) != raw { out.append((code, .int(raw))) }
            }
        }
        if let t = target.temperature, let code = tempCode {
            let r = tempRange
            let raw = Int((r.lowerBound + t * (r.upperBound - r.lowerBound)).rounded())
            if force || status[code]?.doubleValue.map({ Int($0) }) != raw { out.append((code, .int(raw))) }
        }
        return out
    }

    func colourJSON(h: Double, s: Double, v: Double) -> String {
        let hi = Int(h.rounded()) % 361
        let si = Int((s * svMax).rounded()), vi = Int((max(0.01, v) * svMax).rounded())
        return "{\"h\":\(hi),\"s\":\(si),\"v\":\(max(isV1 ? 1 : 10, vi))}"
    }
}

// MARK: - Local data point translation

extension Light {
    /// Standard light layouts, used when Tuya didn't give us the mapping.
    static let v2Map = ["20": "switch_led", "21": "work_mode", "22": "bright_value_v2", "23": "temp_value_v2", "24": "colour_data_v2", "25": "scene_data_v2", "26": "countdown_1"]
    static let v1Map = ["1": "switch_led", "2": "work_mode", "3": "bright_value", "4": "temp_value", "5": "colour_data"]

    func codeMap(seen: [String: JSONValue]? = nil) -> [String: String] {
        if !dpMap.isEmpty { return dpMap }
        let keys = Set(seen?.keys.map { $0 } ?? Array(status.keys))
        if keys.contains("20") || brightCode == "bright_value_v2" { return Self.v2Map }
        return Self.v1Map
    }

    func dpID(for code: String) -> String? {
        codeMap().first { $0.value == code }?.key
    }

    /// Cloud-format command values -> local dps.
    func localDPS(_ cmds: [(String, JSONValue)]) -> [String: JSONValue]? {
        var out: [String: JSONValue] = [:]
        for (code, value) in cmds {
            guard let dp = dpID(for: code) else { return nil }
            if code.hasPrefix("colour_data"), let raw = value.stringValue, let hsv = Self.parseColour(raw, svMax: svMax) {
                out[dp] = .string(isV1 || code == "colour_data" ? Self.hexV1(hsv) : Self.hexV2(hsv))
            } else {
                out[dp] = value
            }
        }
        return out
    }

    /// Local dps -> cloud-format status.
    func cloudStatus(_ dps: [String: JSONValue]) -> [String: JSONValue] {
        let map = codeMap(seen: dps)
        var out: [String: JSONValue] = [:]
        for (dp, value) in dps {
            guard let code = map[dp] else { continue }
            if code.hasPrefix("colour_data"), let hex = value.stringValue, let hsv = Self.parseHex(hex, v1: code == "colour_data" || isV1) {
                out[code] = .string(colourJSON(h: hsv.h, s: hsv.s, v: hsv.v))
            } else {
                out[code] = value
            }
        }
        return out
    }

    /// v2: HHHHSSSSVVVV, s and v 0...1000.
    static func hexV2(_ c: HSV) -> String {
        String(format: "%04x%04x%04x", Int(c.h.rounded()) % 361, Int((c.s * 1000).rounded()), Int((c.v * 1000).rounded()))
    }

    /// v1: RRGGBB0HHHSSVV, s and v 0...255.
    static func hexV1(_ c: HSV) -> String {
        let (r, g, b) = rgb(c)
        return String(format: "%02x%02x%02x%04x%02x%02x", r, g, b, Int(c.h.rounded()) % 361, Int((c.s * 255).rounded()), Int((c.v * 255).rounded()))
    }

    static func parseHex(_ hex: String, v1: Bool) -> HSV? {
        let chars = Array(hex)
        func n(_ a: Int, _ len: Int) -> Double? {
            guard a + len <= chars.count else { return nil }
            return Int(String(chars[a..<(a + len)]), radix: 16).map(Double.init)
        }
        if chars.count == 12 && !v1, let h = n(0, 4), let s = n(4, 4), let v = n(8, 4) {
            return HSV(h: h, s: min(1, s / 1000), v: min(1, v / 1000))
        }
        if chars.count == 14, let h = n(6, 4), let s = n(10, 2), let v = n(12, 2) {
            return HSV(h: h, s: s / 255, v: v / 255)
        }
        if chars.count == 12, let h = n(0, 4), let s = n(4, 4), let v = n(8, 4) {
            return HSV(h: h, s: min(1, s / 1000), v: min(1, v / 1000))
        }
        return nil
    }

    static func rgb(_ c: HSV) -> (Int, Int, Int) {
        let h = (c.h.truncatingRemainder(dividingBy: 360)) / 60, s = c.s, v = c.v
        let i = Int(h), f = h - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        let rgb: (Double, Double, Double)
        switch i {
        case 0: rgb = (v, t, p)
        case 1: rgb = (q, v, p)
        case 2: rgb = (p, v, t)
        case 3: rgb = (p, q, v)
        case 4: rgb = (t, p, v)
        default: rgb = (v, p, q)
        }
        return (Int(rgb.0 * 255), Int(rgb.1 * 255), Int(rgb.2 * 255))
    }
}

// MARK: - Storage

enum LightStore {
    static func load() -> [Light] { (AppGroup.read([Light].self, "lights.json") ?? []).sorted { $0.order < $1.order } }
    static func save(_ list: [Light]) {
        AppGroup.write(list, "lights.json")
        AppGroup.write(list.filter { !$0.hidden }.map(LightSnap.init), "snaps.json")
    }
    static func visible() -> [Light] { load().filter { !$0.hidden } }

    static func update(_ id: String, _ change: (inout Light) -> Void) {
        var list = load()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        save(list)
    }

    static func snaps() -> [LightSnap] { AppGroup.read([LightSnap].self, "snaps.json") ?? [] }
}

/// Small copy for widgets and Control Center.
struct LightSnap: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var isOn: Bool
    var percent: Int
    var online: Bool
    var colourMode: Bool
    var colour: Light.HSV?
    var temperature: Double?
    var canDim: Bool

    init(_ l: Light) {
        id = l.id; name = l.name; isOn = l.isOn; percent = l.percent; online = l.online
        colourMode = l.isColourMode; colour = l.colour; temperature = l.temperature; canDim = l.canDim
    }

    var tint: Color { Light.tint(colourMode: colourMode, colour: colour, temperature: temperature) }

    static let previews: [LightSnap] = {
        func make(_ n: String, _ on: Bool, _ p: Int, _ t: Double) -> LightSnap {
            var info = DeviceInfo(id: n, name: n, category: "dj", productName: "", online: true, status: ["switch_led": .bool(on), "bright_value_v2": .int(p * 10), "temp_value_v2": .int(Int(t * 1000))])
            info.localKey = nil
            return LightSnap(Light(info: info))
        }
        return [make("Desk lamp", true, 60, 0.2), make("Bedroom", false, 40, 0.1), make("Strip", true, 25, 0.6), make("Ceiling", false, 100, 0.5)]
    }()
}
