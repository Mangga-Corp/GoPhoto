//
//  MotionService.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//
//  MotionService.swift
//  gophoto
//
//  Core layer: the ONLY place that talks to the motion sensors (CoreMotion).
//

import CoreMotion

// MARK: - Model

/// Phone tilt in degrees, assuming the phone is held upright (portrait).
nonisolated struct DeviceTilt: Equatable, Sendable {
    /// Sideways tilt. 0 = horizon level. Positive = rotated clockwise.
    let roll: Double
    /// Forward/back tilt. 0 = camera pointing straight ahead. Positive = pointing down.
    let pitch: Double

    /// Converts the raw gravity vector (from CoreMotion) into angles.
    init(gravityX x: Double, gravityY y: Double, gravityZ z: Double) {
        roll  = atan2(x, -y) * 180 / .pi
        pitch = asin(max(-1, min(1, -z))) * 180 / .pi
    }
}

// MARK: - Protocol

nonisolated protocol MotionServiceProtocol: AnyObject {
    func tiltUpdates() -> AsyncStream<DeviceTilt>
}

// MARK: - Real implementation

nonisolated final class MotionService: MotionServiceProtocol, @unchecked Sendable {

    private let hub: MotionHub

    init(hub: MotionHub = .shared) {
        self.hub = hub
    }

    /// A stream of tilt readings (~30 per second).
    /// The sensor starts when someone listens and stops automatically when they stop listening.
    func tiltUpdates() -> AsyncStream<DeviceTilt> {
        AsyncStream { continuation in
            let id = hub.subscribe(.tilt, deliver: { sample in
                continuation.yield(
                    DeviceTilt(gravityX: sample.gravityX, gravityY: sample.gravityY, gravityZ: sample.gravityZ)
                )
            }, finish: {
                continuation.finish()
            })
            guard let id else {
                continuation.finish()   // e.g. Simulator: no sensors
                return
            }

            continuation.onTermination = { [hub] _ in
                hub.unsubscribe(id)
            }
        }
    }
}
