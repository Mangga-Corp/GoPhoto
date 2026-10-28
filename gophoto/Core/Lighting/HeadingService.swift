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

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func headingUpdates() -> AsyncStream<CameraHeading?> {
        AsyncStream { continuation in
            guard motionManager.isDeviceMotionAvailable,
                  CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else {
                continuation.finish()
                return
            }

            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: queue) { motion, _ in
                guard let motion else { return }
                let m = motion.attitude.rotationMatrix
                continuation.yield(CameraHeading(m31: m.m31, m32: m.m32,
                                                 magneticAccuracy: motion.magneticField.accuracy))
            }

            continuation.onTermination = { _ in
                self.motionManager.stopDeviceMotionUpdates()
            }
        }
    }
}
