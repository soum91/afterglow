import Foundation

enum AutomationEvent: String, CaseIterable, Codable, Identifiable {
    case none, clock, sunset, lastLight, cloudy, roomAbove, roomBelow, outsideAbove, outsideBelow

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Off"
        case .clock: return "Time of day"
        case .sunset: return "Sunset"
        case .lastLight: return "Last light (civil dusk)"
        case .cloudy: return "Becomes cloudy"
        case .roomAbove: return "Room temperature rises above"
        case .roomBelow: return "Room temperature drops below"
        case .outsideAbove: return "Outside temperature rises above"
        case .outsideBelow: return "Outside temperature drops below"
        }
    }

    var needsWeather: Bool { self == .cloudy || self == .outsideAbove || self == .outsideBelow }
    var needsTemperature: Bool { self == .roomAbove || self == .roomBelow || self == .outsideAbove || self == .outsideBelow }
    var isSolar: Bool { self == .sunset || self == .lastLight }
}

enum AutomationConditionKind: String, CaseIterable, Codable, Identifiable {
    case none, roomAbove, roomBelow, outsideAbove, outsideBelow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "No temperature condition"
        case .roomAbove: return "Room above"
        case .roomBelow: return "Room below"
        case .outsideAbove: return "Outside above"
        case .outsideBelow: return "Outside below"
        }
    }
}

struct SceneAutomation: Codable, Hashable {
    var event: AutomationEvent = .none
    var minuteOfDay = 19 * 60
    var solarOffsetMinutes = 0
    var temperatureC = 25.0
    var cloudThreshold = 75
    var timeWindow = false
    var windowStart = 18 * 60
    var windowEnd = 23 * 60
    var onlyIfCloudy = false
    var condition: AutomationConditionKind = .none
    var conditionTemperatureC = 25.0
    var fadeSeconds = 0

    func bridgePayload(id: String) -> [String: Any] {
        ["id": id, "event": event.rawValue, "at": minuteOfDay, "offset": solarOffsetMinutes,
         "threshold": temperatureC, "cloud": cloudThreshold,
         "window": timeWindow, "from": windowStart, "to": windowEnd,
         "onlyCloudy": onlyIfCloudy, "condition": condition.rawValue,
         "conditionTemp": conditionTemperatureC, "fade": fadeSeconds]
    }
}
