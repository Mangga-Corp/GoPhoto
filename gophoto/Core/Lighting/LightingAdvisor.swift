//
//  LightingAdvisor.swift
//  gophoto
//
//  Core layer: pure logic, no network or sensors. Turns the weather, the sun and what the user's
//  own photos prefer into one lighting recommendation for photographing people.
//
//  What can really be applied: an iPhone's aperture is fixed, so the f-numbers here are
//  guidance only. The only setting the app applies is the slowest shutter (a cap on auto
//  exposure, so ISO makes up the difference). The ISO range is guidance too. The exposure bias
//  is never changed: backlit people are brightened after the shot (`BacklightController`).
//

import Foundation

/// The weather as the lighting rules need it (WeatherKit is mapped to this in `WeatherService`).
nonisolated enum LightingWeather: Sendable, Equatable {
    case clear, cloudy, rain, heavyRain, mist
}

/// The situation a rule is written for. Night, golden hour and heavy rain are out of the four
/// basic weathers; `unknown` is the fallback when weather and sun are both unavailable.
nonisolated enum LightingScene: String, Sendable, CaseIterable {
    case sunny, overcast, rainy, misty
    case heavyRain, goldenHour, night
    case unknown
}

/// How bright and airy (or dark and moody) the user's reference photos look.
nonisolated enum LightStyle: String, Sendable, Codable, CaseIterable {
    case bright, balanced, moody
}

nonisolated struct PhotoIdea: Sendable, Equatable {
    let text: String
    /// Preferences this idea suits; ideas that suit the user's style come first.
    let styles: Set<LightStyle>
}

/// Camera values worth aiming for with a person in the frame. Written once per scene.
nonisolated struct LightingRule: Sendable, Equatable {
    let title: String
    /// f-number range: guidance only (fixed aperture on iPhone).
    let aperture: ClosedRange<Double>
    /// Slowest shutter to allow, seconds (applied as the shutter cap), and the fastest the light
    /// usually gives (guidance only).
    let slowestShutter: TimeInterval
    let fastestShutter: TimeInterval
    /// ISO range: guidance only.
    let iso: ClosedRange<Int>
    let ideas: [PhotoIdea]
}

nonisolated struct LightingRecommendation: Sendable, Equatable {
    let scene: LightingScene
    let rule: LightingRule
    /// Up to `LightingAdvisor.ideaCount` ideas, the user's style first.
    let ideas: [PhotoIdea]
    /// Shutter no slower than this (seconds) while the camera picks the exposure.
    var slowestShutter: TimeInterval { rule.slowestShutter }
}

/// The preference read from the user's photos (`PresetAnalysis.lightLevel`).
nonisolated struct LightPreference: Sendable, Equatable {
    /// Median mean luminance of the reference photos, 0...1.
    let level: Double

    static let brightFrom = 0.55
    static let moodyUpTo = 0.40

    var style: LightStyle {
        if level >= Self.brightFrom { return .bright }
        if level <= Self.moodyUpTo { return .moody }
        return .balanced
    }
}

nonisolated enum LightingAdvisor {

    static let ideaCount = 2

    /// Sun this low (or lower) above the horizon is night.
    static let nightAltitude = 0.0

    static func scene(weather: LightingWeather?, sun: SunPosition?) -> LightingScene {
        if let sun {
            if sun.altitude <= nightAltitude { return .night }
            if sun.isGoldenHour { return .goldenHour }
        }
        switch weather {
        case .clear:     return .sunny
        case .cloudy:    return .overcast
        case .rain:      return .rainy
        case .heavyRain: return .heavyRain
        case .mist:      return .misty
        case nil:        return .unknown
        }
    }

    static func recommend(weather: LightingWeather?, sun: SunPosition?,
                          preference: LightPreference?) -> LightingRecommendation {
        let scene = scene(weather: weather, sun: sun)
        let rule = rules[scene] ?? fallback
        let style = preference?.style
        // Stable: ideas that suit the style move up, the rest keep their order.
        let ordered = rule.ideas.enumerated().sorted { a, b in
            let aFits = style.map { a.element.styles.contains($0) } ?? false
            let bFits = style.map { b.element.styles.contains($0) } ?? false
            return aFits != bFits ? aFits : a.offset < b.offset
        }.map(\.element)
        return LightingRecommendation(scene: scene, rule: rule, ideas: Array(ordered.prefix(ideaCount)))
    }

    // MARK: Rules
    //
    // Shutter: a person who moves a little blurs below about 1/125 s, and hand shake adds to it,
    // so people rules start at 1/125 (not the 1/60 that suits a still scene). Bright scenes can
    // go far above it; dim ones (rain, mist, night) are held at the floor and ISO pays for it.
    // Aperture: portraits want subject separation, so the wide end of the lens is the aim; this is
    // guidance because the phone's aperture is fixed. ISO: base ISO when bright, up when dim.

    static let fallback = LightingRule(
        title: "Even light",
        aperture: 1.8...4, slowestShutter: 1.0 / 125, fastestShutter: 1.0 / 1000, iso: 50...800,
        ideas: [
            PhotoIdea(text: "Face the light so it falls softly on their face", styles: [.bright, .balanced]),
            PhotoIdea(text: "Look for a plain background to keep attention on them", styles: [.bright, .balanced, .moody]),
        ])

    static let rules: [LightingScene: LightingRule] = [
        .sunny: LightingRule(
            title: "Sunny",
            aperture: 1.8...5.6, slowestShutter: 1.0 / 250, fastestShutter: 1.0 / 4000, iso: 50...200,
            ideas: [
                PhotoIdea(text: "Open shade or a wall's shadow for soft, even skin", styles: [.bright, .balanced]),
                PhotoIdea(text: "Shadow play: leaf or fence patterns across the face", styles: [.moody]),
                PhotoIdea(text: "Silhouette against the bright sky", styles: [.moody]),
                PhotoIdea(text: "A sun flare past their shoulder", styles: [.bright, .balanced]),
            ]),
        .overcast: LightingRule(
            title: "Overcast",
            aperture: 1.8...4, slowestShutter: 1.0 / 125, fastestShutter: 1.0 / 1000, iso: 100...400,
            ideas: [
                PhotoIdea(text: "Soft, even light: no squinting, flattering skin", styles: [.bright, .balanced]),
                PhotoIdea(text: "Bold colours in clothes pop against the grey sky", styles: [.bright, .balanced]),
                PhotoIdea(text: "Low, moody sky as a quiet backdrop", styles: [.moody]),
            ]),
        .rainy: LightingRule(
            title: "Rainy",
            aperture: 1.8...4, slowestShutter: 1.0 / 125, fastestShutter: 1.0 / 800, iso: 200...800,
            ideas: [
                PhotoIdea(text: "Reflections in puddles beside them", styles: [.moody, .balanced]),
                PhotoIdea(text: "Raindrops on a window or umbrella in the frame", styles: [.moody, .balanced]),
                PhotoIdea(text: "A bright umbrella against a dull street", styles: [.bright]),
            ]),
        .misty: LightingRule(
            title: "Misty",
            aperture: 1.8...4, slowestShutter: 1.0 / 125, fastestShutter: 1.0 / 500, iso: 100...800,
            ideas: [
                PhotoIdea(text: "Fading layers: let the mist soften the background", styles: [.moody, .balanced]),
                PhotoIdea(text: "Glowing street lights behind them", styles: [.moody]),
                PhotoIdea(text: "Silhouette in the haze", styles: [.moody, .balanced]),
            ]),
        .heavyRain: LightingRule(
            title: "Heavy rain",
            aperture: 1.8...2.8, slowestShutter: 1.0 / 100, fastestShutter: 1.0 / 500, iso: 400...1600,
            ideas: [
                PhotoIdea(text: "Keep the phone dry: shoot from a doorway or under cover", styles: [.bright, .balanced, .moody]),
                PhotoIdea(text: "Window drops with them blurred behind", styles: [.moody, .balanced]),
            ]),
        .goldenHour: LightingRule(
            title: "Golden hour",
            aperture: 1.8...4, slowestShutter: 1.0 / 125, fastestShutter: 1.0 / 1000, iso: 50...400,
            ideas: [
                PhotoIdea(text: "Warm side light: stand so the sun is beside them", styles: [.bright, .balanced]),
                PhotoIdea(text: "Sun behind them for a glowing rim around the hair", styles: [.bright, .moody]),
                PhotoIdea(text: "Long shadows along the ground", styles: [.moody]),
            ]),
        .night: LightingRule(
            title: "Low light",
            aperture: 1.8...2.8, slowestShutter: ExposureLimits.slowestShutter, fastestShutter: 1.0 / 250, iso: 800...3200,
            ideas: [
                PhotoIdea(text: "Stand near a light source so it falls on their face", styles: [.bright, .balanced, .moody]),
                PhotoIdea(text: "Bright lights glowing behind them", styles: [.moody, .balanced]),
            ]),
    ]
}
