import Foundation
import CoreLocation
import UIKit
import UserNotifications
import WidgetKit

/// Arrive/leave triggers for Home or scene-specific places, using iOS region monitoring. iOS wakes (or relaunches)
/// Afterglow in the background when you cross the boundary, even if the app was swiped away,
/// as long as location access is set to Always.
@MainActor
final class Geo: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = Geo()

    struct Home: Codable, Equatable {
        var lat: Double
        var lon: Double
        var radius: Double
    }

    @Published var home: Home? {
        didSet {
            if let home, let d = try? JSONEncoder().encode(home) {
                UserDefaults.standard.set(d, forKey: "geo.home")
            } else {
                UserDefaults.standard.removeObject(forKey: "geo.home")
            }
            sync()
        }
    }
    @Published private(set) var auth: CLAuthorizationStatus
    @Published private(set) var locating = false
    @Published var lastEvent: String? = UserDefaults.standard.string(forKey: "geo.lastEvent")

    private let lm: CLLocationManager
    private let homeRegionID = "afterglow.home"
    private let sceneRegionPrefix = "afterglow.scene."
    private var pendingRadius: Double = 300
    private var awaitingHomeLocation = false

    override init() {
        let manager = CLLocationManager()
        lm = manager
        auth = manager.authorizationStatus
        super.init()
        if let d = UserDefaults.standard.data(forKey: "geo.home"),
           let h = try? JSONDecoder().decode(Home.self, from: d) {
            home = h   // observers don't fire inside init
        }
        lm.delegate = self
        sync()
    }

    var hasAlways: Bool { auth == .authorizedAlways }

    var anyTriggers: Bool {
        SceneStore.load().contains { $0.hasLocationTrigger }
    }

    func requestAccess() {
        switch lm.authorizationStatus {
        case .notDetermined: lm.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: lm.requestAlwaysAuthorization()
        default: break
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func setHomeHere(radius: Double) {
        pendingRadius = radius
        awaitingHomeLocation = true
        requestAccess()
        locating = true
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.requestLocation()
    }

    func setHome(lat: Double, lon: Double, radius: Double) {
        awaitingHomeLocation = false
        guard CLLocationCoordinate2DIsValid(CLLocationCoordinate2D(latitude: lat, longitude: lon)) else { return }
        home = Home(lat: lat, lon: lon, radius: radius)
    }

    func clearHome() {
        awaitingHomeLocation = false
        locating = false
        home = nil
    }

    func setRadius(_ r: Double) {
        guard var h = home else { return }
        h.radius = r
        home = h
    }

    /// Sync the Home region plus one region per scene with a custom location.
    /// iOS supports at most 20 monitored regions per app.
    func sync() {
        for region in lm.monitoredRegions where region.identifier == homeRegionID || region.identifier.hasPrefix(sceneRegionPrefix) {
            lm.stopMonitoring(for: region)
        }
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let enabled = SceneStore.load().filter { $0.hasLocationTrigger }
        var places: [(String, Home)] = []
        if let home, enabled.contains(where: { $0.triggerLocation == nil }) {
            places.append((homeRegionID, home))
        }
        for scene in enabled {
            guard let point = scene.triggerLocation else { continue }
            places.append((sceneRegionPrefix + scene.id,
                           Home(lat: point.lat, lon: point.lon, radius: point.radius)))
        }

        for (identifier, place) in places.prefix(20) {
            let coordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
            guard CLLocationCoordinate2DIsValid(coordinate) else { continue }
            let maximum = lm.maximumRegionMonitoringDistance
            let radius = maximum > 0 ? min(place.radius, maximum) : place.radius
            let region = CLCircularRegion(center: coordinate, radius: max(100, radius), identifier: identifier)
            region.notifyOnEntry = true
            region.notifyOnExit = true
            lm.startMonitoring(for: region)
        }
    }

    // MARK: Delegate (CoreLocation calls back on the main thread, where the manager was made)

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let s = m.authorizationStatus
        MainActor.assumeIsolated {
            auth = s
            if s == .authorizedWhenInUse { lm.requestAlwaysAuthorization() }
            sync()
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        MainActor.assumeIsolated {
            locating = false
            guard awaitingHomeLocation else { return }
            awaitingHomeLocation = false
            home = Home(lat: l.coordinate.latitude, lon: l.coordinate.longitude, radius: pendingRadius)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { locating = false; awaitingHomeLocation = false }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == "afterglow.home" || region.identifier.hasPrefix("afterglow.scene.") else { return }
        MainActor.assumeIsolated { fire(arrive: true, regionID: region.identifier) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == "afterglow.home" || region.identifier.hasPrefix("afterglow.scene.") else { return }
        MainActor.assumeIsolated { fire(arrive: false, regionID: region.identifier) }
    }

    // MARK: Running scenes

    private func fire(arrive: Bool, regionID: String) {
        let scenes = SceneStore.load().filter { scene in
            guard (arrive ? scene.onArrive : scene.onLeave) == true else { return false }
            return scene.triggerLocation == nil
                ? home != nil && regionID == homeRegionID
                : regionID == sceneRegionPrefix + scene.id
        }
        guard !scenes.isEmpty else { return }
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "geo-scene") {
            UIApplication.shared.endBackgroundTask(bg)
        }
        Task { @MainActor in
            for s in scenes {
                let what = arrive ? "Arrived at trigger location" : "Left trigger location"
                do {
                    try await SceneEngine.run(s)
                    note("\(what): ran \(s.name)")
                } catch {
                    note("\(what): \(s.name) failed (\(error.localizedDescription))")
                }
            }
            AppStore.shared.lights = LightStore.load()
            AppStore.shared.scenes = SceneStore.load()
            WidgetCenter.shared.reloadAllTimelines()
            UIApplication.shared.endBackgroundTask(bg)
        }
    }

    private func note(_ text: String) {
        let stamp = Date().formatted(date: .abbreviated, time: .shortened)
        lastEvent = "\(text) · \(stamp)"
        UserDefaults.standard.set(lastEvent, forKey: "geo.lastEvent")
        let c = UNMutableNotificationContent()
        c.title = "Afterglow"
        c.body = text
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}
