import Foundation
import CoreLocation

/// Runtime guard for arrival/departure scenes. Scheduled rules are evaluated by
/// Keystone; these conditions also apply to iOS geofence callbacks.
@MainActor
enum SceneConditions {
    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let cloud_cover: Int
        }
        let current: Current
    }

    static func evaluate(_ rule: SceneAutomation?, indoorC: Double?) async -> Bool {
        guard let rule else { return true }
        if rule.timeWindow {
            let components = Calendar.current.dateComponents([.hour, .minute], from: .now)
            let now = (components.hour ?? 0) * 60 + (components.minute ?? 0)
            let start = rule.windowStart, end = rule.windowEnd
            if start != end && !(start < end ? now >= start && now < end : now >= start || now < end) {
                return false
            }
        }

        let needsWeather = rule.onlyIfCloudy || rule.condition == .outsideAbove || rule.condition == .outsideBelow
        let weather = needsWeather ? await currentWeather() : nil
        if rule.onlyIfCloudy && (weather?.cloud_cover ?? -1) < rule.cloudThreshold { return false }

        let threshold = rule.conditionTemperatureC
        switch rule.condition {
        case .none: return true
        case .roomAbove: return indoorC.map { $0 >= threshold } ?? false
        case .roomBelow: return indoorC.map { $0 <= threshold } ?? false
        case .outsideAbove: return weather.map { $0.temperature_2m >= threshold } ?? false
        case .outsideBelow: return weather.map { $0.temperature_2m <= threshold } ?? false
        }
    }

    private static func currentWeather() async -> Forecast.Current? {
        guard let home = Geo.shared.home else { return nil }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        url?.queryItems = [
            URLQueryItem(name: "latitude", value: String(home.lat)),
            URLQueryItem(name: "longitude", value: String(home.lon)),
            URLQueryItem(name: "current", value: "temperature_2m,cloud_cover"),
            URLQueryItem(name: "timezone", value: "UTC")
        ]
        guard let target = url?.url else { return nil }
        var request = URLRequest(url: target)
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let forecast = try? JSONDecoder().decode(Forecast.self, from: data) else { return nil }
        return forecast.current
    }
}
