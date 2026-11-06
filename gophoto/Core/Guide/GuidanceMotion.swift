//
//  GuidanceMotion.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import Foundation

/// Up or down. Used by both the height and the tilt animation.
nonisolated enum Direction: Equatable, Sendable, CaseIterable {
    case up, down

    var opposite: Direction { self == .up ? .down : .up }

    /// +1 for up, -1 for down. Handy for animation maths in later parts.
    var sign: Double { self == .up ? 1 : -1 }
}

/// From which side the 3D phone is seen while it tilts.
/// `yawDegrees`: 0 = straight from the front, positive = the viewer moves to the phone's LEFT
/// (so the phone's left side becomes visible).
nonisolated enum TiltView: Equatable, Sendable {
    /// Version 1: straight from the front.
    case frontFacing
    /// Version 2: seen from the left at 45 degrees.
    case angledLeft45
    /// Version 2b: seen from the right at 45 degrees.
    case angledRight45
    /// Version 3: yaw comes from data (user's preference). Nil or invalid falls back to 45.
    case preferenceDriven(degrees: Double?)

    static let fallbackYawDegrees: Double = -45
    static let yawRange: ClosedRange<Double> = -60...60

    var yawDegrees: Double {
        switch self {
        case .frontFacing:               0
        case .angledLeft45:              45
        case .angledRight45:             -45
        case .preferenceDriven(let raw): Self.sanitizedYaw(raw)
        }
    }

    /// Nil, NaN or infinite -> fallback. Otherwise clamped to `yawRange`.
    static func sanitizedYaw(_ raw: Double?) -> Double {
        guard let raw, raw.isFinite else { return fallbackYawDegrees }
        return min(max(raw, yawRange.lowerBound), yawRange.upperBound)
    }
}

/// What to animate.
nonisolated enum GuidanceMotion: Equatable, Sendable {
    /// Move the phone up or down (phone, dashed ghost, chevrons).
    case height(Direction)
    /// Tilt the phone around its bottom edge by `degrees`, seen from `view`.
    case tilt(Direction, degrees: Double, view: TiltView)

    /// How far the tilt animation swings, in degrees. Always inside this range so the motion
    /// stays readable (tiny errors still show a visible swing, huge ones do not flip the phone).
    static let tiltDegreesRange: ClosedRange<Double> = 12...40
    /// Used when there is no usable pitch error.
    static let tiltFallbackDegrees: Double = 25

    /// - Parameters:
    ///   - instruction: what the guide wants the photographer to do.
    ///   - pitchError: phone pitch minus target, degrees (same value as `CameraViewModel.pitchError`).
    ///     Only its size is used (for the swing); the direction always comes from `instruction`.
    ///   - tiltView: which tilt version to show.
    /// - Returns: nil for instructions that have no animation (distance, left/right, straighten, ...).
    init?(instruction: GuideInstruction, pitchError: Double? = nil, tiltView: TiltView = .frontFacing) {
        switch instruction {
        case .raisePhone, .raisePhoneKeepAngle:
            self = .height(.up)
        case .lowerPhone, .lowerPhoneKeepAngle:
            self = .height(.down)
        case .tiltUp:
            self = .tilt(.up, degrees: Self.tiltDegrees(forPitchError: pitchError), view: tiltView)
        case .tiltDown:
            self = .tilt(.down, degrees: Self.tiltDegrees(forPitchError: pitchError), view: tiltView)
        case .findPerson, .moveCloser, .moveFarther, .moveLeft, .moveRight,
             .moveHigher, .moveLower, .setPhoneHeight, .straighten, .holdStill,
             .waitForZoom, .keepSteady:
            return nil
        }
    }

    /// |pitchError| clamped to `tiltDegreesRange`; nil, NaN or infinite -> `tiltFallbackDegrees`.
    static func tiltDegrees(forPitchError pitchError: Double?) -> Double {
        guard let pitchError, pitchError.isFinite else { return tiltFallbackDegrees }
        return min(max(abs(pitchError), tiltDegreesRange.lowerBound), tiltDegreesRange.upperBound)
    }

    var direction: Direction {
        switch self {
        case .height(let d):  d
        case .tilt(let d, _, _): d
        }
    }
}
