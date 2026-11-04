//
//  PersonLossZoomReset.swift
//  gophoto
//
//  Adaptive zoom when nobody is in frame: keep the current zoom for a short grace period (a
//  detector miss of a few frames must not change it), then step back to the 1.0x baseline at the
//  adaptive zoom's own rate. Fed by the existing person detection (one update per analysed frame,
//  about 15 per second); pure, so it can be checked without a camera.
//

import Foundation

nonisolated struct PersonLossZoomReset: Sendable {
    /// How long nobody may be detected before the zoom returns to the baseline.
    static let gracePeriod: TimeInterval = 1.5
    /// Longest time one step may cover, so a late frame can't make the return jump.
    static let maxStepInterval: TimeInterval = 0.2
    /// At the baseline (no more zoom commands): only rounding noise away from it.
    static let atBaselineEpsilon = 1e-6
    /// A last step this close to the baseline lands on it exactly (no 1.0001x left over).
    static let snapMargin = 0.005

    enum Action: Equatable, Sendable {
        /// A person is visible: the adaptive zoom decides.
        case personVisible
        /// Nobody detected, still within the grace period: keep the current zoom.
        case waiting
        /// Nobody detected and the zoom is already at the baseline: nothing to do.
        case atBaseline
        /// Apply this zoom: the next step towards the baseline (the baseline itself on the last step).
        case step(to: Double)
    }

    /// When the person was last lost (nil while visible, or after a pause).
    private(set) var lostSince: TimeInterval?
    private var lastStepAt: TimeInterval?

    /// - Parameters:
    ///   - ratePerSecond: largest zoom change per second (the adaptive zoom's own limit).
    mutating func update(personVisible: Bool, currentZoom: Double, baseline: Double,
                         ratePerSecond: Double, now: TimeInterval) -> Action {
        guard !personVisible else {
            lostSince = nil
            lastStepAt = nil
            return .personVisible
        }
        guard let lostSince else {
            self.lostSince = now
            return .waiting
        }
        guard now - lostSince >= Self.gracePeriod else { return .waiting }

        let distance = baseline - currentZoom
        guard abs(distance) > Self.atBaselineEpsilon else {
            lastStepAt = nil
            return .atBaseline
        }
        let interval = min(max(now - (lastStepAt ?? now - Self.maxStepInterval), 0), Self.maxStepInterval)
        let maxDelta = ratePerSecond * interval
        lastStepAt = now
        if abs(distance) <= maxDelta + Self.snapMargin { return .step(to: baseline) }
        return .step(to: currentZoom + (distance > 0 ? maxDelta : -maxDelta))
    }

    /// Frames stopped arriving (camera stopped, e.g. under the gallery): the grace period starts
    /// again when they resume, so a gap in frames is not taken for a lost person.
    mutating func pause() {
        lostSince = nil
        lastStepAt = nil
    }
}
