//
//  HeadingService.swift
//  gophoto
//
//  Core layer: the ONLY place that reads where the back camera points. Uses the device's -z axis
//  in the `xTrueNorthZVertical` frame, not the compass heading (which follows the top of the phone).
//

import CoreMotion

/// Where the back camera points, degrees clockwise from true north.
nonisolated struct CameraHeading: Equatable, Sendable {
    let degrees: Double
    /// False while the compass is uncalibrated or the camera looks almost straight up or down.
    let isReliable: Bool

    /// Camera looking steeper than this (share of its direction that is horizontal) has no heading.
    static let minHorizontalShare = 0.3

    /// - Parameter m31, m32, m33: the third row of `CMAttitude.rotationMatrix`, which is the
    ///   device z axis written in the reference frame (x = true north, y = west, z = up).
    ///   The camera looks along -z: north = -m31, east = +m32, up = -m33.
    init?(m31: Double, m32: Double, magneticAccuracy: CMMagneticFieldCalibrationAccuracy) {
        let north = -m31, east = m32
        guard hypot(north, east) >= Self.minHorizontalShare else { return nil }
        var heading = atan2(east, north) * 180 / .pi
        if heading < 0 { heading += 360 }
        degrees = heading
        isReliable = magneticAccuracy == .medium || magneticAccuracy == .high
    }
}

nonisolated protocol HeadingServiceProtocol: AnyObject {
    /// Camera headings (~10 per second) while someone listens. Finishes at once when true north
    /// is not available (Simulator, location services off).
    func headingUpdates() -> AsyncStream<CameraHeading?>
}

nonisolated final class HeadingService: HeadingServiceProtocol, @unchecked Sendable {

    private let hub: MotionHub

    init(hub: MotionHub = .shared) {
        self.hub = hub
    }

    /// The hub delivers ~30 readings per second; one in this many is passed on (~10 per second).
    private static let keepEvery = 3

    func headingUpdates() -> AsyncStream<CameraHeading?> {
        AsyncStream { continuation in
            let counter = Counter()
            let id = hub.subscribe(.heading, deliver: { sample in
                guard counter.next() % Self.keepEvery == 0 else { return }
                continuation.yield(CameraHeading(m31: sample.m31, m32: sample.m32,
                                                 magneticAccuracy: sample.magneticAccuracy))
            }, finish: {
                continuation.finish()
            })
            guard let id else {
                continuation.finish()
                return
            }

            continuation.onTermination = { [hub] _ in
                hub.unsubscribe(id)
            }
        }
    }

    /// Counts readings; only ever touched from the hub's serial queue.
    private final class Counter: @unchecked Sendable {
        private var value = 0
        func next() -> Int {
            value += 1
            return value
        }
    }
}
