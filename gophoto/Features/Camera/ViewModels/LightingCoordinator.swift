//
//  LightingCoordinator.swift
//  gophoto
//
//  Gathers the light-related inputs (sun, compass, brightness) and decides the one tip shown to
//  the photographer. It never touches the camera: the exposure bias belongs to `CameraService`.
//

import Observation
import CoreLocation

@Observable
final class LightingCoordinator {

    /// The tip on screen, or nil.
    private(set) var suggestion: SunSuggestion?

    /// Debug panel: what the decision is based on.
    private(set) var sunPosition: SunPosition?
    private(set) var heading: CameraHeading?

    @ObservationIgnored private var guidance = SunGuidance()
    @ObservationIgnored private var location: CLLocation?
    @ObservationIgnored private var lastHeadingAt: TimeInterval = 0
    @ObservationIgnored private let locationService: LocationServiceProtocol
    @ObservationIgnored private let headingService: HeadingServiceProtocol
    @ObservationIgnored private let sunService: SunService

    /// A heading older than this is not used (camera backgrounded, sensor paused).
    private static let headingMaxAge: TimeInterval = 2

    init(locationService: LocationServiceProtocol = LocationService(),
         headingService: HeadingServiceProtocol = HeadingService(),
         sunService: SunService = SunService()) {
        self.locationService = locationService
        self.headingService = headingService
        self.sunService = sunService
    }

    /// Finds where the phone is (asks for permission the first time); nothing is stored.
    func refreshLocation() async {
        location = await locationService.currentLocation()
        if location == nil { sunPosition = nil }
    }

    /// Follows where the camera points until the View's .task is cancelled.
    func observeHeading() async {
        for await next in headingService.headingUpdates() {
            heading = next
            lastHeadingAt = ProcessInfo.processInfo.systemUptime
        }
        heading = nil
    }

    /// One brightness reading from the camera (about twice a second).
    func ingest(_ exposure: ExposureStatus, hasPerson: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let sun = location.map { sunService.position(at: Date(), location: $0) }
        let fresh = now - lastHeadingAt < Self.headingMaxAge
        let heading = fresh ? heading.flatMap { $0.isReliable ? $0.degrees : nil } : nil
        let next = guidance.update(SunConditions(sun: sun, cameraHeading: heading,
                                                 frameLuminance: exposure.frameLuminance,
                                                 faceLuminance: exposure.faceLuminance,
                                                 hasPerson: hasPerson))
        if sun != sunPosition { sunPosition = sun }
        if next != suggestion { suggestion = next }
    }

    /// The camera stopped: tips would be stale when it comes back.
    func reset() {
        guidance = SunGuidance()
        suggestion = nil
    }
}
