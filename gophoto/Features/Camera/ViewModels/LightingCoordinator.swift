//
//  LightingCoordinator.swift
//  gophoto
//
//  Gathers the light-related inputs (sun, compass, weather, brightness, the user's preference) and
//  decides what the photographer sees: at most one sun tip, and the lighting recommendation for the
//  weather. It never touches the camera: the exposure bias belongs to `CameraService`, and the
//  recommended shutter cap is handed to the camera by the view model.
//

import Observation
import CoreLocation

@Observable
final class LightingCoordinator {

    /// The sun tip on screen, or nil. While one shows, the recommendation stays hidden so the two
    /// never talk over each other.
    private(set) var suggestion: SunSuggestion?
    /// The weather recommendation to show, or nil (indoors, or nothing known about the light).
    private(set) var recommendation: LightingRecommendation?

    /// Debug panel: what the decisions are based on.
    private(set) var sunPosition: SunPosition?
    private(set) var heading: CameraHeading?
    private(set) var weather: LightingWeather?
    /// Slowest shutter the recommendation asks the camera for; nil when none applies.
    private(set) var slowestShutter: TimeInterval?

    @ObservationIgnored private var guidance = SunGuidance()
    @ObservationIgnored private var location: CLLocation?
    @ObservationIgnored private var lightLevel: Double?
    @ObservationIgnored private var isOutdoor = false
    @ObservationIgnored private var lastHeadingAt: TimeInterval = 0
    @ObservationIgnored private let locationService: LocationServiceProtocol
    @ObservationIgnored private let weatherService: WeatherServiceProtocol
    @ObservationIgnored private let headingService: HeadingServiceProtocol
    @ObservationIgnored private let sunService: SunService

    /// A heading older than this is not used (camera backgrounded, sensor paused).
    private static let headingMaxAge: TimeInterval = 2
    /// Frame brightness to count as outdoors, and the lower one to stop (no flicker at the edge).
    private static let outdoorEnter = SunRules.standard.outdoorLuminance
    private static let outdoorExit = 0.30

    init(locationService: LocationServiceProtocol = LocationService(),
         weatherService: WeatherServiceProtocol = WeatherKitService(),
         headingService: HeadingServiceProtocol = HeadingService(),
         sunService: SunService = SunService()) {
        self.locationService = locationService
        self.weatherService = weatherService
        self.headingService = headingService
        self.sunService = sunService
    }

    /// Finds where the phone is (asks for permission the first time) and the weather there.
    /// Nothing is stored. Without permission or network the rules fall back on what is known.
    func refreshLocation() async {
        location = await locationService.currentLocation()
        guard let location else {
            sunPosition = nil
            weather = nil
            return
        }
        weather = await weatherService.currentWeather(at: location)
    }

    /// The user's photo preference (`PresetAnalysis.lightLevel`); nil when not analysed yet.
    func setLightLevel(_ level: Double?) {
        lightLevel = level
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
        let tip = guidance.update(SunConditions(sun: sun, cameraHeading: heading,
                                                frameLuminance: exposure.frameLuminance,
                                                faceLuminance: exposure.faceLuminance,
                                                hasPerson: hasPerson))

        isOutdoor = exposure.frameLuminance >= (isOutdoor ? Self.outdoorExit : Self.outdoorEnter)
        let advice = LightingAdvisor.recommend(weather: weather, sun: sun,
                                               preference: lightLevel.map(LightPreference.init))
        // Indoors the weather says nothing about the light (night is dark by itself: no gate).
        let applies = advice.scene != .unknown && (isOutdoor || advice.scene == .night)

        if sun != sunPosition { sunPosition = sun }
        if tip != suggestion { suggestion = tip }
        let shown = applies ? advice : nil
        if shown != recommendation { recommendation = shown }
        let shutter = shown?.slowestShutter
        if shutter != slowestShutter { slowestShutter = shutter }
    }

    /// The camera stopped: tips would be stale when it comes back.
    func reset() {
        guidance = SunGuidance()
        suggestion = nil
        recommendation = nil
        slowestShutter = nil
    }
}
