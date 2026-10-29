//
//  LightTip.swift
//  gophoto
//
//  Core layer: pure logic. The sun (`SunGuidance`) and the backlight meter (`BacklightController`)
//  can both have something to say at once. This picks the one tip the photographer sees.
//

import Foundation

nonisolated enum LightTip: Equatable, Sendable {
    case sun(SunSuggestion)
    case backlight(BacklightTip)

    /// One tip out of the two sources, most useful first:
    /// 1. Move left/right: measured from the picture, and the only tip that says which way to go.
    /// 2. Sun swap: the compass and the picture agree, and the wording names the sun.
    /// 3. Backlight swap: the picture alone says so (any light, indoors too).
    /// 4. Harsh sun overhead.
    /// 5. Golden hour: a pleasant note, never over a problem.
    static func choose(sun: SunSuggestion?, backlight: BacklightTip?) -> LightTip? {
        switch (sun, backlight) {
        case (_, .moveLeft?), (_, .moveRight?):
            return backlight.map(LightTip.backlight)
        case (.swapPlaces?, _):
            return .sun(.swapPlaces)
        case (_, .swapPlaces?):
            return .backlight(.swapPlaces)
        case (let sun?, nil):
            return .sun(sun)
        case (nil, nil):
            return nil
        }
    }
}
