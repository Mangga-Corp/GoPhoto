//
//  BacklightController.swift
//  gophoto
//
//  Core layer: pure logic, no camera or sensors. Notices a backlit person (face much darker than
//  the frame) and says where the photographer should move so the light falls on the face. The
//  photo itself is never changed: a camera cannot make a backlit face bright without blowing out
//  the background, so the fix is a better position, as a photographer with any camera would do.
//

import Foundation

/// Where to move for a backlit person.
nonisolated enum BacklightTip: Equatable, Sendable {
    /// The light is straight behind them: trade places so it is behind the photographer.
    case swapPlaces
    /// The light comes from behind them on this side of the frame: walk around them to that side
    /// (they turn to keep facing the camera) until it falls on their face.
    case moveLeft, moveRight
}

nonisolated struct BacklightController: Sendable {

    struct Tuning: Sendable, Equatable {
        /// Backlit when the face is darker than this share of the frame's brightness...
        var enterRatio = 0.70
        /// ...and the light is back to normal above this share (the gap is the hysteresis).
        var exitRatio = 0.85
        /// Dim scenes are skipped: a dark room is not backlight.
        var minFrameLuminance = 0.20
        /// One side of the background brighter than the other by this share means the light comes
        /// from that side; less than this and it counts as straight behind.
        var sideDifference = 0.15
        /// The side that "has the light" must itself be at least this bright: two dark walls that
        /// differ a little say nothing about where the light comes from.
        var minSideLuminance = 0.25
        /// A face this dark (entering) / this dark (leaving) against a bright area behind the
        /// person is backlit even when the frame average is low (a dark room with a window).
        var darkFaceEnter = 0.25
        var darkFaceExit = 0.30
        /// The brightest area behind the person counts as a light from this brightness up, and the
        /// face is backlit when darker than this share of it (entering) / of it (leaving).
        var minPeakLuminance = 0.40
        var peakEnterRatio = 0.35
        var peakExitRatio = 0.50
        /// Seconds of backlight before the tip shows, so a passing glance does not trigger it.
        var confirmDelay: TimeInterval = 1.0
        /// Seconds without backlight (or without a face) before the tip goes away.
        var resetDelay: TimeInterval = 1.0
    }

    private let tuning: Tuning
    /// The tip to show; it keeps its direction until the backlight is gone.
    private(set) var tip: BacklightTip?
    private(set) var isBacklit = false
    private var backlitSince: TimeInterval?
    private var lastBacklitAt: TimeInterval?

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Back to the neutral state (camera stopped or restarted).
    mutating func reset() {
        tip = nil
        isBacklit = false
        backlitSince = nil
        lastBacklitAt = nil
    }

    /// One measurement. `faceLuminance` is nil when nobody was found; `peakLuminance` is the
    /// brightest area behind the person; `leftLuminance` and `rightLuminance` are the background
    /// beside the person (nil when that side is too narrow).
    mutating func update(faceLuminance: Double?, frameLuminance: Double, peakLuminance: Double,
                         leftLuminance: Double?, rightLuminance: Double?, now: TimeInterval) -> BacklightTip? {
        isBacklit = Self.isBacklit(faceLuminance: faceLuminance, frameLuminance: frameLuminance,
                                   peakLuminance: peakLuminance, wasBacklit: isBacklit, tuning: tuning)
        if isBacklit {
            lastBacklitAt = now
            let since = backlitSince ?? now
            backlitSince = since
            if tip == nil, now - since >= tuning.confirmDelay {
                tip = Self.direction(left: leftLuminance, right: rightLuminance, tuning: tuning)
            }
        } else if let last = lastBacklitAt, now - last < tuning.resetDelay {
            // Backlight may be back in a moment (a face flicker): keep the tip for now.
        } else {
            tip = nil
            backlitSince = nil
            lastBacklitAt = nil
        }
        return tip
    }

    /// The brighter side of the background is where the light comes from.
    static func direction(left: Double?, right: Double?, tuning: Tuning = Tuning()) -> BacklightTip {
        guard let left, let right, max(left, right) >= tuning.minSideLuminance,
              abs(left - right) / max(left, right) >= tuning.sideDifference else { return .swapPlaces }
        return left > right ? .moveLeft : .moveRight
    }

    /// Two ways to be backlit: the face is much darker than the frame, or (a dark room, where the
    /// frame average is low) the face is dark against a bright light behind the person.
    private static func isBacklit(faceLuminance: Double?, frameLuminance: Double, peakLuminance: Double,
                                  wasBacklit: Bool, tuning: Tuning) -> Bool {
        guard let faceLuminance else { return false }
        if frameLuminance >= tuning.minFrameLuminance {
            let ratio = faceLuminance / frameLuminance
            if wasBacklit ? ratio <= tuning.exitRatio : ratio < tuning.enterRatio { return true }
        }
        guard peakLuminance >= tuning.minPeakLuminance else { return false }
        let ratio = faceLuminance / peakLuminance
        return wasBacklit
            ? faceLuminance <= tuning.darkFaceExit && ratio <= tuning.peakExitRatio
            : faceLuminance < tuning.darkFaceEnter && ratio < tuning.peakEnterRatio
    }
}
