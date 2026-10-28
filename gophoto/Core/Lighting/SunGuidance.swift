//
//  SunGuidance.swift
//  gophoto
//
//  Core layer: pure logic, no sensors. Turns the sun's position, where the camera points and how
//  bright the face is into at most one tip for the photographer (S1).
//

import Foundation

nonisolated enum SunSuggestion: Equatable, Sendable {
    case swapPlaces       // camera faces the sun, face is dark
    case findShade        // sun high overhead
    case goldenHour
}

/// The sun, from SunKit (degrees; azimuth clockwise from true north).
nonisolated struct SunPosition: Equatable, Sendable {
    let azimuth: Double
    let altitude: Double
    let isGoldenHour: Bool
}

/// Everything one decision needs. Optional values are nil when their source is off or unsure.
nonisolated struct SunConditions: Equatable, Sendable {
    /// Nil without location permission or a location: the feature stays silent.
    var sun: SunPosition?
    /// Where the back camera points, degrees from true north. Nil when the compass is unsure.
    var cameraHeading: Double?
    var frameLuminance: Double
    var faceLuminance: Double?
    var hasPerson: Bool
}

nonisolated struct SunRules: Sendable, Equatable {
    /// Camera within this angle of the sun → the sun is behind the subject (from-side: 45°–135° is fine).
    var backlitEnterAngle = 45.0
    /// A little wider to leave, so the tip doesn't flicker at the border.
    var backlitExitAngle = 55.0
    /// Sun higher than this (above the horizon) is harsh overhead light.
    var harshSunAltitude = 60.0
    /// Frame brightness that counts as outdoors, and as "very bright" (needed for the swap tip).
    var outdoorLuminance = 0.35
    var veryBrightLuminance = 0.5
    /// Face darker than this share of the frame (entering) / of this share (leaving).
    var faceDarkerEnter = 0.8
    var faceDarkerExit = 0.9

    static let standard = SunRules()
}

nonisolated struct SunGuidance: Sendable {
    private let rules: SunRules
    private(set) var current: SunSuggestion?
    private var hasShownGoldenHour = false

    init(rules: SunRules = .standard) {
        self.rules = rules
    }

    /// The tip for these conditions, or nil. "Golden hour" is given once, then never again.
    mutating func update(_ conditions: SunConditions) -> SunSuggestion? {
        let next = Self.suggestion(for: conditions, current: current, rules: rules,
                                   canShowGoldenHour: !hasShownGoldenHour)
        if next == .goldenHour { hasShownGoldenHour = true }
        current = next
        return next
    }

    /// Smallest angle between two compass directions, 0...180.
    static func angle(between a: Double, and b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }

    private static func suggestion(for c: SunConditions, current: SunSuggestion?, rules: SunRules,
                                   canShowGoldenHour: Bool) -> SunSuggestion? {
        guard let sun = c.sun, sun.altitude > 0, c.frameLuminance >= rules.outdoorLuminance else { return nil }

        if c.hasPerson, sun.altitude > rules.harshSunAltitude { return .findShade }

        if c.hasPerson, let heading = c.cameraHeading, let face = c.faceLuminance,
           c.frameLuminance >= rules.veryBrightLuminance {
            let wasSwap = current == .swapPlaces
            let facingSun = angle(between: sun.azimuth, and: heading)
                <= (wasSwap ? rules.backlitExitAngle : rules.backlitEnterAngle)
            let faceDark = face < c.frameLuminance * (wasSwap ? rules.faceDarkerExit : rules.faceDarkerEnter)
            if facingSun, faceDark { return .swapPlaces }
        }

        if sun.isGoldenHour, canShowGoldenHour || current == .goldenHour { return .goldenHour }
        return nil
    }
}
