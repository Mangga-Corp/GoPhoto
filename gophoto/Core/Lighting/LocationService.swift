//
//  LocationService.swift
//  gophoto
//
//  Core layer: the ONLY place that talks to CoreLocation. "When In Use" permission only; the
//  location is kept in memory for the sun and weather lookups and is never saved.
//

import CoreLocation

protocol LocationServiceProtocol: AnyObject {
    /// Asks for permission the first time. Nil when denied, restricted or no fix could be found.
    func currentLocation() async -> CLLocation?
}

final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var permissionContinuation: CheckedContinuation<Bool, Never>?
    private var fixContinuation: CheckedContinuation<CLLocation?, Never>?
    /// A fix this young is reused: the sun and the weather barely move in a few minutes.
    private var lastFix: CLLocation?
    private static let maxFixAge: TimeInterval = 15 * 60

    override init() {
        super.init()
        manager.delegate = self
        // The sun needs the city, not the street.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentLocation() async -> CLLocation? {
        if let lastFix, Date().timeIntervalSince(lastFix.timestamp) < Self.maxFixAge { return lastFix }
        guard await isAuthorized(), fixContinuation == nil else { return nil }
        let fix = await withCheckedContinuation { continuation in
            fixContinuation = continuation
            manager.requestLocation()
        }
        lastFix = fix ?? lastFix
        return fix
    }

    private func isAuthorized() async -> Bool {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: return true
        case .notDetermined:
            guard permissionContinuation == nil else { return false }
            return await withCheckedContinuation { continuation in
                permissionContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default: return false
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let granted = manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
        permissionContinuation?.resume(returning: granted)
        permissionContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        fixContinuation?.resume(returning: locations.last)
        fixContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fixContinuation?.resume(returning: nil)
        fixContinuation = nil
    }
}
