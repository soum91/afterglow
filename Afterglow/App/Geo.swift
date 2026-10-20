import Foundation
import CoreLocation
import UIKit
import UserNotifications
import WidgetKit

/// Arrive/leave-home triggers for scenes, using iOS region monitoring. iOS wakes (or relaunches)
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
    private let regionID = "afterglow.home"
    private var pendingRadius: Double = 300

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
        requestAccess()
        locating = true
        lm.desiredAccuracy = kCLLocationAccuracyBest
        lm.requestLocation()
    }

    func setRadius(_ r: Double) {
        guard var h = home else { return }
        h.radius = r
        home = h
    }

    /// Start or stop the geofence to match the saved home and the scenes that use it.
    func sync() {
        for r in lm.monitoredRegions where r.identifier == regionID { lm.stopMonitoring(for: r) }
        guard let home, anyTriggers, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: home.lat, longitude: home.lon),
                                      radius: min(home.radius, lm.maximumRegionMonitoringDistance),
                                      identifier: regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        lm.startMonitoring(for: region)
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
            home = Home(lat: l.coordinate.latitude, lon: l.coordinate.longitude, radius: pendingRadius)
        }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { locating = false }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == "afterglow.home" else { return }
        MainActor.assumeIsolated { fire(arrive: true) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == "afterglow.home" else { return }
        MainActor.assumeIsolated { fire(arrive: false) }
    }

    // MARK: Running scenes

    private func fire(arrive: Bool) {
        let scenes = SceneStore.load().filter { arrive ? $0.onArrive == true : $0.onLeave == true }
        guard !scenes.isEmpty else { return }
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "geo-scene") {
            UIApplication.shared.endBackgroundTask(bg)
        }
        Task { @MainActor in
            for s in scenes {
                let what = arrive ? "Arrived home" : "Left home"
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
