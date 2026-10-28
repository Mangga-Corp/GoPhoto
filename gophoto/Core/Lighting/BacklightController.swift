//
//  BacklightController.swift
//  gophoto
//
//  Core layer: pure logic, no camera or sensors. Decides how much a backlit person needs to be
//  brightened. The camera's exposure is not changed (that would wash out the background): the lift
//  is applied to the people only, after the shot, by `PersonRelight`.
//

import Foundation

nonisolated struct BacklightController: Sendable {

    struct Tuning: Sendable, Equatable {
        /// Backlit when the face is darker than this share of the frame's brightness...
        var enterRatio = 0.55
        /// ...and the light is back to normal above this share (the gap is the hysteresis).
        var exitRatio = 0.80
        /// Dim scenes are skipped: a dark room is not backlight.
        var minFrameLuminance = 0.25
        /// Face brightness the lift aims for (0...1, as encoded in the frame).
        var targetFaceLuminance = 0.42
        /// Most the people may be lifted, EV.
        var maxLift = 1.5
        /// How fast the lift follows the measurement (share of the gap closed per reading).
        var smoothing = 0.5
        /// Seconds without backlight (or without a face) before the lift goes back to 0.
        var resetDelay: TimeInterval = 1.0
    }

    private let tuning: Tuning
    /// EV to brighten the people by right now; 0 when there is no backlight.
    private(set) var lift = 0.0
    private(set) var isBacklit = false
    private var lastBacklitAt: TimeInterval?

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Back to the neutral state (camera stopped or restarted).
    mutating func reset() {
        lift = 0
        isBacklit = false
        lastBacklitAt = nil
    }

    /// One measurement. `faceLuminance` is nil when no face was found. Returns the lift now.
    mutating func update(faceLuminance: Double?, frameLuminance: Double, now: TimeInterval) -> Double {
        isBacklit = Self.isBacklit(faceLuminance: faceLuminance, frameLuminance: frameLuminance,
                                   wasBacklit: isBacklit, tuning: tuning)
        if isBacklit, let faceLuminance {
            lastBacklitAt = now
            // Encoded brightness doubles for about one EV of lift in the dark tones people sit in.
            let needed = min(max(log2(tuning.targetFaceLuminance / max(faceLuminance, 0.01)), 0), tuning.maxLift)
            lift += tuning.smoothing * (needed - lift)
        } else if let last = lastBacklitAt, now - last < tuning.resetDelay {
            // Backlight may be back in a moment (a face flicker): hold the lift for now.
        } else {
            lift = 0
            lastBacklitAt = nil
        }
        return lift
    }

    private static func isBacklit(faceLuminance: Double?, frameLuminance: Double,
                                  wasBacklit: Bool, tuning: Tuning) -> Bool {
        guard let faceLuminance, frameLuminance >= tuning.minFrameLuminance else { return false }
        let ratio = faceLuminance / frameLuminance
        return wasBacklit ? ratio <= tuning.exitRatio : ratio < tuning.enterRatio
    }
}
