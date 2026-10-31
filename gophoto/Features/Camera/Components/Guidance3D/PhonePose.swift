//
//  PhonePose.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import Foundation

nonisolated struct PhonePose: Equatable, Sendable {
    /// Turn around the vertical axis through the phone's centre.
    /// Positive = we see the phone's LEFT side (same convention as `TiltView.yawDegrees`).
    var yawDegrees: Double = 0
    /// Lean around the phone's BOTTOM edge.
    /// Positive = top edge moves AWAY from the viewer (camera aims up, "tilt up").
    /// Negative = top edge comes toward the viewer ("tilt down").
    var tiltUpDegrees: Double = 0
    /// Lift in metres, positive = up. Unused until the height animation (Part 3).
    var liftMeters: Double = 0

    static let front = PhonePose()
    static let left45 = PhonePose(yawDegrees: 45)
    static let tiltedUp25 = PhonePose(tiltUpDegrees: 25)
    static let left45TiltedUp25 = PhonePose(yawDegrees: 45, tiltUpDegrees: 25)

    /// Finite and clamped, so a bad value can never break the scene.
    var sanitized: PhonePose {
        func clean(_ value: Double, limit: Double) -> Double {
            value.isFinite ? min(max(value, -limit), limit) : 0
        }
        return PhonePose(yawDegrees: clean(yawDegrees, limit: 90),
                         tiltUpDegrees: clean(tiltUpDegrees, limit: 75),
                         liftMeters: clean(liftMeters, limit: 0.5))
    }
}
