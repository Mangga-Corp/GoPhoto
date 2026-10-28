//
//  BacklightController.swift
//  gophoto
//
//  Core layer: pure logic, no camera or sensors. Decides how much exposure bias a backlit face
//  needs. `CameraService` feeds it measurements and applies the answer.
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
        /// Face brightness the bias aims for (0...1, as encoded in the frame), and how far from it
        /// is still "close enough" (no change inside this band, so the bias doesn't pump).
        var targetFaceLuminance = 0.42
        var tolerance = 0.05
        /// EV added or removed per measurement.
        var step = 0.25
        /// Most the bias may rise, EV (the sky may turn white: the face has priority).
        var maxBias = 1.0
        /// Seconds without backlight (or without a face) before the bias goes back to 0.
        var resetDelay: TimeInterval = 1.0
    }

    /// Slowest shutter allowed while the bias is raised; the missing light comes from ISO (spec A2).
    static let slowestShutter: TimeInterval = 1.0 / 60

    private let tuning: Tuning
    private(set) var bias = 0.0
    private(set) var isBacklit = false
    private var lastBacklitAt: TimeInterval?

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Back to the neutral state (camera stopped or restarted).
    mutating func reset() {
        bias = 0
        isBacklit = false
        lastBacklitAt = nil
    }

    /// One measurement. `faceLuminance` is nil when no face was found. `biasRange` is what the
    /// camera accepts. Returns the bias the camera should have now.
    mutating func update(faceLuminance: Double?, frameLuminance: Double,
                         biasRange: ClosedRange<Double>, now: TimeInterval) -> Double {
        isBacklit = Self.isBacklit(faceLuminance: faceLuminance, frameLuminance: frameLuminance,
                                   wasBacklit: isBacklit, tuning: tuning)
        if isBacklit, let faceLuminance {
            lastBacklitAt = now
            let error = tuning.targetFaceLuminance - faceLuminance
            if error > tuning.tolerance {
                bias += tuning.step
            } else if error < -tuning.tolerance {
                bias -= tuning.step
            }
        } else if let last = lastBacklitAt, now - last < tuning.resetDelay {
            // Backlight may be back in a moment (a face flicker): hold the bias for now.
        } else {
            bias = 0
            lastBacklitAt = nil
        }
        bias = min(max(bias, 0), min(tuning.maxBias, biasRange.upperBound))
        return max(bias, biasRange.lowerBound)
    }

    private static func isBacklit(faceLuminance: Double?, frameLuminance: Double,
                                  wasBacklit: Bool, tuning: Tuning) -> Bool {
        guard let faceLuminance, frameLuminance >= tuning.minFrameLuminance else { return false }
        let ratio = faceLuminance / frameLuminance
        return wasBacklit ? ratio <= tuning.exitRatio : ratio < tuning.enterRatio
    }
}
