//
//  EnhancedLook.swift
//  gophoto
//
//  The five AI Enhanced looks of the gallery viewer. A look is not a fixed filter: it is a
//  *direction* (warmer, fresher, softer, deeper…) that is scaled per photo by the measurements in
//  `PhotoStatistics`, so a photo that already leans that way is moved less, and a dull one more.
//
//  Natural by design: every shift is clamped to a small range and the whole result is mixed back
//  over the original (`strength` ≤ `maxStrength`). Colours are never pushed to an obvious "filter".
//

import Foundation

nonisolated enum EnhancedLook: String, CaseIterable, Identifiable, Sendable {
    case natural, warm, fresh, soft, deep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural"
        case .warm:    "Warm"
        case .fresh:   "Fresh"
        case .soft:    "Soft"
        case .deep:    "Deep"
        }
    }

    var summary: String {
        switch self {
        case .natural: "Balanced exposure and colour"
        case .warm:    "Gentle golden tone"
        case .fresh:   "Clean, bright and crisp"
        case .soft:    "Smooth skin, calm tones"
        case .deep:    "Richer contrast and depth"
        }
    }

    // MARK: - Limits (the "not too heavy" guarantee)

    /// The most of the graded image that is ever mixed over the original.
    static let maxStrength: Float = 0.85
    /// Largest white-balance shift of a look (kelvin, + = warmer). Absolute, not on top of the
    /// tuner's own +350 K, so the looks differ clearly: Warm and Fresh sit on opposite sides of Natural.
    static let maxWarmthShift: Float = 1000
    static let saturationRange: ClosedRange<Float> = 0.92...1.12
    static let contrastRange: ClosedRange<Float> = 0.94...1.12
    static let exposureRange: ClosedRange<Float> = -0.2...0.3

    /// Settings for this look: `base` (from `EnhanceTuner`, already fitted to the photo) plus the
    /// look's shifts, each scaled by how much this photo needs it.
    func settings(from base: PhotoEnhancer.Settings, stats: PhotoStatistics) -> PhotoEnhancer.Settings {
        let dark = EnhanceTuner.ramp(stats.meanLuminance, from: 0.42, to: 0.20)
        let bright = EnhanceTuner.ramp(stats.meanLuminance, from: 0.62, to: 0.82)
        let flat = EnhanceTuner.ramp(stats.contrast, from: 0.22, to: 0.10)
        let punchy = 1 - flat
        let dull = EnhanceTuner.ramp(stats.saturation, from: 0.30, to: 0.10)
        let vivid = 1 - dull
        let warmCast = EnhanceTuner.ramp(stats.colorCast, from: 0.02, to: 0.12)
        let coolCast = EnhanceTuner.ramp(stats.colorCast, from: 0.0, to: -0.10)
        let noisy = EnhanceTuner.ramp(stats.noise, from: 0.006, to: 0.026)

        var s = base
        // Light: pull the average towards a pleasant mid-tone instead of a fixed brightness change.
        func exposure(target: Double) -> Float {
            Float((target - stats.meanLuminance) * 0.9)
        }
        var warmth: Float = 0   // the look's final white-balance shift in kelvin

        switch self {
        case .natural:
            s.strength = base.strength
            warmth = 150 * Float(1 - warmCast)                  // near neutral: the reference look
            s.exposureEV = exposure(target: 0.46)
            s.saturation = 1 + 0.05 * Float(dull)

        case .warm:
            s.strength = max(base.strength, 0.8)
            warmth = 900 * Float(1 - 0.6 * warmCast)            // already warm → moved less
            s.tint = 6 * Float(1 - warmCast)                    // a touch of magenta keeps skin healthy
            s.exposureEV = exposure(target: 0.47)
            s.saturation = 1 + 0.06 * Float(1 - warmCast)
            s.contrast = 1.02
            s.vignette = base.vignette * 0.8

        case .fresh:
            s.strength = max(base.strength, 0.8)
            warmth = -600 * Float(1 - 0.6 * coolCast)           // already cool → moved less
            s.tint = -3 * Float(1 - coolCast)
            s.exposureEV = exposure(target: 0.52) + 0.05 * Float(1 - bright)
            s.saturation = 1 + 0.04 * Float(dull)
            s.contrast = 1.03 + 0.03 * Float(flat)
            s.shadowLift = 0.25 * Float(dark)
            s.clarity = base.clarity * 1.1 * Float(1 - 0.5 * noisy)
            s.vignette = 0.05

        case .soft:
            s.strength = base.strength * 0.85
            warmth = 200 * Float(1 - warmCast)
            s.exposureEV = exposure(target: 0.50)
            s.saturation = 0.96 + 0.03 * Float(dull)
            s.contrast = 0.97
            s.shadowLift = 0.2 + 0.2 * Float(dark)
            s.skinSmoothing = stats.hasFace ? min(0.8, base.skinSmoothing + 0.15) : 0
            s.clarity = base.clarity * 0.4
            s.sharpness = base.sharpness * 0.6
            s.vignette = base.vignette * 0.6

        case .deep:
            s.strength = base.strength * 0.9
            warmth = 120 * Float(1 - warmCast)
            s.exposureEV = exposure(target: 0.42) - 0.03 * Float(bright)
            s.saturation = 1 + 0.06 * Float(1 - vivid * 0.7)
            s.contrast = 1.04 + 0.06 * Float(flat) + 0.01 * Float(punchy)
            s.clarity = base.clarity * 1.2 * Float(1 - 0.5 * noisy)
            s.vignette = base.vignette * 1.2
        }

        s.warmthKelvin = min(max(warmth, -Self.maxWarmthShift), Self.maxWarmthShift)
        s.exposureEV = min(max(s.exposureEV, Self.exposureRange.lowerBound), Self.exposureRange.upperBound)
        s.saturation = min(max(s.saturation, Self.saturationRange.lowerBound), Self.saturationRange.upperBound)
        s.contrast = min(max(s.contrast, Self.contrastRange.lowerBound), Self.contrastRange.upperBound)
        s.strength = min(s.strength, Self.maxStrength)
        return s
    }
}
