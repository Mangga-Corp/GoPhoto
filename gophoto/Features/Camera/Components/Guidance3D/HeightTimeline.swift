//
//  HeightTimeline.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import Foundation

nonisolated struct HeightFrame: Equatable, Sendable {
    /// 0 = start pose, 1 = target pose.
    var progress: Double
    var phoneOpacity: Double
}

nonisolated enum HeightTimeline {
    /// Seamless 2.5-second guidance motion loop.
    static let period: Double = 2.5

    /// Reduce Motion: phone at the start, fully visible, nothing moves.
    static let stillFrame = HeightFrame(progress: 0, phoneOpacity: 1)

    static func frame(atTime seconds: Double) -> HeightFrame {
        guard seconds.isFinite else { return stillFrame }
        return frame(atPhase: seconds / period)
    }

    /// Phase wraps continuously without any jump or discontinuity.
    static func frame(atPhase rawPhase: Double) -> HeightFrame {
        guard rawPhase.isFinite else { return stillFrame }
        let p = rawPhase - rawPhase.rounded(.down)

        let progress: Double
        switch p {
        case ..<0.52:
            // Glide smoothly from start to target (0 -> 1)
            let u = p / 0.52
            progress = smoothGlide(u)
        case ..<0.68:
            // Hold at target pose (1.0)
            progress = 1.0
        case ..<0.92:
            // Return smoothly from target back to start (1 -> 0)
            let u = (p - 0.68) / 0.24
            progress = 1.0 - smoothGlide(u)
        default:
            // Rest briefly at start pose (0.0) before seamlessly looping
            progress = 0.0
        }

        return HeightFrame(progress: progress, phoneOpacity: 1.0)
    }

    // MARK: - Helpers

    /// Sine-based ease-in-out: zero velocity and acceleration at endpoints for seamless looping.
    private static func smoothGlide(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        return 0.5 * (1.0 - cos(t * Double.pi))
    }
}
