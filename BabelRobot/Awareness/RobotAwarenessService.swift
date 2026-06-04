//
//  RobotAwarenessService.swift
//  BabelRobot
//
//  Gives the robot a sense of context — time, place, weather and connectivity —
//  so it knows roughly *when* and *where* it is. This is the ONLY part of the
//  app that reaches the network for the robot's own knowledge (LLM inference
//  stays 100% local). It is opt-in, and every external lookup is written to the
//  `AwarenessLog` so it can be followed and audited.
//
//  Sources:
//   • Time / locale  — the system clock (no network, no permission).
//   • Location       — CoreLocation (city-level accuracy; needs permission).
//   • Place name     — Apple reverse-geocoding (network).
//   • Weather        — Open-Meteo (no API key; network).
//   • Connectivity   — NWPathMonitor (no network call, no permission).
//

import Foundation
import Observation
import CoreLocation
import Network

@MainActor
@Observable
final class RobotAwarenessService: NSObject, CLLocationManagerDelegate {

    // MARK: - Settings

    /// Master switch. Off by default — the robot is otherwise fully offline.
    var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            UserDefaults.standard.set(enabled, forKey: Self.key)
            enabled ? start() : stop()
        }
    }

    // MARK: - Observable context

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var isOnline = false
    private(set) var connectionType: String?
    private(set) var coordinate: CLLocationCoordinate2D?
    /// e.g. "Lisbon, Portugal".
    private(set) var place: String?
    /// e.g. "17°C · Clear".
    private(set) var weather: String?
    private(set) var lastRefresh: Date?

    let log = AwarenessLog()

    // MARK: - Private

    private static let key = "awareness.enabled"
    private let locationManager = CLLocationManager()
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "robot.awareness.network")
    private var geocoder: CLGeocoder?
    private var startedMonitor = false

    // MARK: - Init

    override init() {
        enabled = UserDefaults.standard.bool(forKey: Self.key)
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer // city-level is enough
        authorization = locationManager.authorizationStatus
        if enabled { start() }
    }

    // MARK: - Derived summaries

    /// Part of day, weekday and local time — always available, no network.
    var timeContext: String {
        let now = Date()
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let part: String
        switch hour {
        case 5..<12:  part = "morning"
        case 12..<17: part = "afternoon"
        case 17..<22: part = "evening"
        default:      part = "night"
        }
        let f = DateFormatter()
        f.dateFormat = "EEEE HH:mm"
        return "\(f.string(from: now)) (\(part))"
    }

    /// A single human-readable line, e.g.
    /// "Tuesday 18:22 (evening) · Lisbon, Portugal · 17°C · Clear · online".
    var contextSummary: String {
        var parts = [timeContext]
        if let place { parts.append(place) }
        if let weather { parts.append(weather) }
        parts.append(isOnline ? "online" : "offline")
        return parts.joined(separator: " · ")
    }

    /// A sentence suitable for injecting into the assistant's system prompt so
    /// answers can be time/place aware. `nil` when awareness is off.
    var systemContextLine: String? {
        guard enabled else { return nil }
        var s = "Current context — local time: \(timeContext)"
        if let place { s += "; location: \(place)" }
        if let weather { s += "; weather: \(weather)" }
        s += "; network: \(isOnline ? "online" : "offline")."
        return s
    }

    // MARK: - Lifecycle

    private func start() {
        startNetworkMonitor()
        log.record(.time, "Awareness on — \(timeContext)")
        // Ask for permission if we don't have an answer yet.
        if authorization == .notDetermined {
            log.record(.permission, "Requesting location permission")
            locationManager.requestWhenInUseAuthorization() // shows the system prompt
        } else if isAuthorized {
            requestLocation()
        }
    }

    private func stop() {
        locationManager.stopUpdatingLocation()
        if startedMonitor { monitor.cancel(); startedMonitor = false }
        log.record(.time, "Awareness off")
    }

    /// Re-read location → place → weather on demand.
    func refresh() {
        guard enabled else { return }
        if isAuthorized { requestLocation() }
        else if authorization == .notDetermined { locationManager.requestWhenInUseAuthorization() }
    }

    private var isAuthorized: Bool {
        authorization == .authorized || authorization == .authorizedAlways
    }

    private func requestLocation() {
        log.record(.location, "Requesting a location fix")
        locationManager.requestLocation()
    }

    // MARK: - Network monitor

    private func startNetworkMonitor() {
        guard !startedMonitor else { return }
        startedMonitor = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            let type = Self.describe(path)
            Task { @MainActor in self?.applyNetwork(online: online, type: type) }
        }
        monitor.start(queue: monitorQueue)
    }

    private func applyNetwork(online: Bool, type: String?) {
        let changed = (online != isOnline) || (type != connectionType)
        isOnline = online
        connectionType = type
        if changed {
            log.record(.network, online ? "Online (\(type ?? "?"))" : "Offline")
        }
    }

    nonisolated private static func describe(_ path: NWPath) -> String? {
        if path.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if path.usesInterfaceType(.wiredEthernet) { return "Ethernet" }
        if path.usesInterfaceType(.cellular) { return "Cellular" }
        if path.status == .satisfied { return "other" }
        return nil
    }

    // MARK: - CLLocationManagerDelegate (arrives on the main thread)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            authorization = manager.authorizationStatus
            log.record(.permission, "Location permission: \(Self.describe(authorization))")
            if isAuthorized, enabled { requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        MainActor.assumeIsolated {
            coordinate = loc.coordinate
            lastRefresh = Date()
            let coordText = String(format: "%.3f, %.3f", loc.coordinate.latitude, loc.coordinate.longitude)
            log.record(.location, "Location fix", detail: coordText)
            reverseGeocode(loc)
            Task { await fetchWeather(for: loc.coordinate) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            log.record(.location, "Location failed", detail: error.localizedDescription)
        }
    }

    // MARK: - Reverse geocoding

    private func reverseGeocode(_ location: CLLocation) {
        let geocoder = CLGeocoder()
        self.geocoder = geocoder
        log.record(.geocode, "Reverse-geocoding the fix (Apple)")
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let p = placemarks?.first {
                    let city = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea
                    let country = p.country
                    let name = [city, country].compactMap { $0 }.joined(separator: ", ")
                    self.place = name.isEmpty ? nil : name
                    self.log.record(.geocode, self.place ?? "Unknown place")
                } else {
                    self.log.record(.geocode, "Geocode failed", detail: error?.localizedDescription)
                }
            }
        }
    }

    // MARK: - Weather (Open-Meteo, no API key)

    private func fetchWeather(for coord: CLLocationCoordinate2D) async {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        comps?.queryItems = [
            .init(name: "latitude", value: String(format: "%.3f", coord.latitude)),
            .init(name: "longitude", value: String(format: "%.3f", coord.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
        ]
        guard let url = comps?.url else { return }
        log.record(.weather, "GET api.open-meteo.com", detail: url.absoluteString)
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let temp = Int(decoded.current.temperature_2m.rounded())
            let desc = Self.weatherDescription(decoded.current.weather_code)
            weather = "\(temp)°C · \(desc)"
            log.record(.weather, weather ?? "—")
        } catch {
            log.record(.weather, "Weather failed", detail: error.localizedDescription)
        }
    }

    private struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        let current: Current
    }

    /// WMO weather interpretation codes → a short label.
    private static func weatherDescription(_ code: Int) -> String {
        switch code {
        case 0:            return "Clear"
        case 1, 2:         return "Partly cloudy"
        case 3:            return "Overcast"
        case 45, 48:       return "Fog"
        case 51, 53, 55:   return "Drizzle"
        case 61, 63, 65:   return "Rain"
        case 66, 67:       return "Freezing rain"
        case 71, 73, 75:   return "Snow"
        case 77:           return "Snow grains"
        case 80, 81, 82:   return "Showers"
        case 85, 86:       return "Snow showers"
        case 95:           return "Thunderstorm"
        case 96, 99:       return "Thunderstorm + hail"
        default:           return "—"
        }
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:      return "not determined"
        case .restricted:         return "restricted"
        case .denied:             return "denied"
        case .authorized,
             .authorizedAlways:   return "authorized"
        @unknown default:         return "unknown"
        }
    }
}
