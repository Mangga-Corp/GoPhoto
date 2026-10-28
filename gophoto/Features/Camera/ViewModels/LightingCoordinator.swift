//
//  LightingCoordinator.swift
//  gophoto
//
//  Gathers the light-related inputs (sun, compass, weather, brightness, the user's preference) and
//  decides what the photographer sees: at most one light tip (sun, else backlight), and the lighting
//  recommendation for the weather. It never touches the camera or the photo: the tips are guidance.
//

import Observation
import CoreLocation

@Observable
final class LightingCoordinator {

    /// The sun tip on screen, or nil. While one shows, the backlight tip and the recommendation
    /// stay hidden so the tips never talk over each other.
    private(set) var suggestion: SunSuggestion?
    /// Where to move because the person is backlit (any light, indoors too), or nil. Shown when
    /// there is no sun tip; it hides the recommendation.
    private(set) var backlightTip: BacklightTip?
    /// The weather recommendation to show, or nil (indoors, or nothing known about the light).
    private(set) var recommendation: LightingRecommendation?

    /// Debug panel: what the decisions are based on.
    private(set) var sunPosition: SunPosition?
    private(set) var heading: CameraHeading?
    private(set) var weather: LightingWeather?
    /// Why the weather is missing (debug panel); nil when it loaded or has not been asked yet.
    private(set) var weatherFailure: String?

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

    /// Runs while the camera is on screen: finds where the phone is (asks for permission the first
    /// time), then follows the camera heading while the weather loads. Nothing is stored. Without
    /// permission or network the rules fall back on what is known.
    func run() async {
        location = await locationService.currentLocation()
        guard let location else {
            sunPosition = nil
            weather = nil
            return
        }
        // The heading needs the location permission answered first (true north).
        let weatherTask = Task {
            weather = await weatherService.currentWeather(at: location)
            weatherFailure = weatherService.lastFailure
        }
        await observeHeading()
        weatherTask.cancel()
    }

    /// The user's photo preference (`PresetAnalysis.lightLevel`); nil when not analysed yet.
    func setLightLevel(_ level: Double?) {
        lightLevel = level
    }

    /// Follows where the camera points until the View's .task is cancelled.
    private func observeHeading() async {
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
        let backlight = tip == nil ? exposure.backlightTip : nil
        if backlight != backlightTip { backlightTip = backlight }
        let shown = applies ? advice : nil
        if shown != recommendation { recommendation = shown }
    }

    /// The camera stopped: tips would be stale when it comes back.
    func reset() {
        guidance = SunGuidance()
        suggestion = nil
        backlightTip = nil
        recommendation = nil
    }
}
