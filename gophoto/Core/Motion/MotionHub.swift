//
//  MotionHub.swift
//  gophoto
//
//  Core layer: the app's ONE CMMotionManager (Apple advises one per app). Tilt and camera heading
//  both read from it. It runs only while someone listens, in the true-north reference frame only
//  while a heading listener exists and true north is usable; otherwise in the default frame, so
//  tilt never depends on location.
//

import CoreMotion
import CoreLocation

/// One device-motion reading, with what tilt and heading each need.
nonisolated struct MotionSample: Sendable {
    let gravityX: Double, gravityY: Double, gravityZ: Double
    /// Third row of the attitude rotation matrix (device z axis in the reference frame).
    let m31: Double, m32: Double
    let magneticAccuracy: CMMagneticFieldCalibrationAccuracy
}

nonisolated final class MotionHub: @unchecked Sendable {

    static let shared = MotionHub()

    enum Need { case tilt, heading }

    private struct Listener {
        let need: Need
        let deliver: @Sendable (MotionSample) -> Void
        let finish: @Sendable () -> Void
    }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let lock = NSLock()
    private var listeners: [UUID: Listener] = [:]
    private var isRunning = false
    private var isTrueNorth = false

    /// ~30 readings per second, as the tilt reading always had.
    private static let interval = 1.0 / 30.0

    /// Starts delivering readings to `deliver` (on the hub's queue). Nil when the sensor, or for
    /// `.heading` true north, is not available (Simulator, no location permission): nothing starts.
    /// `finish` runs if the listener has to be dropped later.
    func subscribe(_ need: Need, deliver: @escaping @Sendable (MotionSample) -> Void,
                   finish: @escaping @Sendable () -> Void) -> UUID? {
        guard manager.isDeviceMotionAvailable else { return nil }
        if need == .heading, !Self.trueNorthUsable { return nil }
        lock.lock()
        defer { lock.unlock() }
        let id = UUID()
        listeners[id] = Listener(need: need, deliver: deliver, finish: finish)
        let wantsTrueNorth = need == .heading || isTrueNorth
        if !isRunning || (wantsTrueNorth && !isTrueNorth) {
            start(trueNorth: wantsTrueNorth)
        }
        return id
    }

    func unsubscribe(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        listeners[id] = nil
        if listeners.isEmpty {
            manager.stopDeviceMotionUpdates()
            isRunning = false
            isTrueNorth = false
        } else if isTrueNorth, !listeners.values.contains(where: { $0.need == .heading }) {
            start(trueNorth: false)       // no heading listener left: drop the magnetometer fusion
        }
    }

    private static var trueNorthUsable: Bool {
        guard CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else { return false }
        let status = CLLocationManager().authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    /// Caller holds the lock.
    private func start(trueNorth: Bool) {
        manager.stopDeviceMotionUpdates()
        manager.deviceMotionUpdateInterval = Self.interval
        isRunning = true
        isTrueNorth = trueNorth
        let handler: CMDeviceMotionHandler = { [weak self] motion, error in
            self?.handle(motion, error)
        }
        if trueNorth {
            manager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: queue, withHandler: handler)
        } else {
            manager.startDeviceMotionUpdates(to: queue, withHandler: handler)
        }
    }

    private func handle(_ motion: CMDeviceMotion?, _ error: Error?) {
        if error != nil {
            dropHeadingListeners()
            return
        }
        guard let motion else { return }
        let g = motion.gravity, m = motion.attitude.rotationMatrix
        let sample = MotionSample(gravityX: g.x, gravityY: g.y, gravityZ: g.z, m31: m.m31, m32: m.m32,
                                  magneticAccuracy: motion.magneticField.accuracy)
        lock.lock()
        let current = Array(listeners.values)
        lock.unlock()
        for listener in current { listener.deliver(sample) }
    }

    /// True north stopped working (for example location was switched off): heading listeners end,
    /// and tilt carries on in the default frame.
    private func dropHeadingListeners() {
        lock.lock()
        guard isTrueNorth else {
            lock.unlock()
            return
        }
        let dropped = listeners.filter { $0.value.need == .heading }
        for id in dropped.keys { listeners[id] = nil }
        if listeners.isEmpty {
            manager.stopDeviceMotionUpdates()
            isRunning = false
            isTrueNorth = false
        } else {
            start(trueNorth: false)
        }
        lock.unlock()
        for listener in dropped.values { listener.finish() }
    }
}
