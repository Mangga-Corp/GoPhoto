//
//  PhasedParameters.swift
//  gophoto
//
//  Experiment parameters of the Phased guide, all in one place. None of these is a final value:
//  each is logged and documented in Docs/Experiments/PhaseGuide/Parameters.md, to be tuned on
//  the phone.
//
import Foundation

/// Size band for `r = live span / reference span`. Enter = to become OK / start an instruction;
/// exit = stays OK (hysteresis); reopen = a finished distance is reopened only outside this.
nonisolated struct SizeBand: Sendable, Equatable {
    var enterLow, enterHigh, exitLow, exitHigh, reopenLow, reopenHigh: Double
}

/// Room kept around the subject in the source frame (frame-height units).
nonisolated struct ShotMargins: Sendable, Equatable {
    var top: Double
    /// Full: below the feet / hem. 3/4 and half: below the cut landmark (knees / hips).
    var bottom: Double
    var side: Double
}

nonisolated struct PhasedParameters: Sendable, Equatable {
    // Time (seconds). Progress is responsive; starting, reversing and completing are slower.
    /// Evidence window for decisions.
    var window: TimeInterval = 0.8
    /// Short window to stop a movement instruction quickly (no overshoot).
    var quickWindow: TimeInterval = 0.3
    /// Longer window for reopen decisions.
    var reopenWindow: TimeInterval = 1.5
    var minSamples = 5
    /// Outside the enter band this long before an instruction starts (also reversals).
    var startDwell: TimeInterval = 0.6
    /// Inside the enter band this long before a phase completes.
    var completeDwell: TimeInterval = 0.8
    /// Evidence for a reopen must last this long.
    var reopenDwell: TimeInterval = 1.5
    /// No valid evidence for this long: the movement instruction is withdrawn (never stale).
    var staleAfter: TimeInterval = 0.5
    /// A movement instruction, once shown, stays at least this long (no blinking).
    var minShow: TimeInterval = 0.8
    /// The green "Hold it there" stays at least this long once shown.
    var holdMinShow: TimeInterval = 0.5
    /// The same instruction does not come back within this time after it was withdrawn.
    var restartCooldown: TimeInterval = 1.0
    /// Subject missing this long before "Point back at the person".
    var lossGrace: TimeInterval = 1.2
    /// After a sustained loss, a candidate far from the last place is only offered for tapping.
    var reacquireDistance: Double = 0.22

    // Vantage (phone height).
    var vantageFacesEnter = 0.4, vantageFacesExit = 0.6, vantageFacesReopen = 1.0
    var vantageDegreesEnter = 3.0, vantageDegreesExit = 5.0, vantageDegreesReopen = 8.0
    /// Highest phone position above the subject's eyes asked for, in face heights (≈ 30 cm / 20 cm).
    var maxLiftFaces = 1.5
    /// Faces smaller than this (frame height) are too small to read the eye line.
    var minFaceHeight = 0.022
    /// Eyes not read (no face, no eye joints, shoulders seen): the eye line 2/5 from the head top
    /// (mask) to the shoulder line.
    var headFromPose = true
    /// The head + shoulders source takes over only after the face has been gone this long, s (Reynard: 1.5).
    var headAfterFaceLoss: TimeInterval = 1.5

    // Tilt.
    /// Reference pitch (Auto crop only). ±4° (Reynard) ≈ the GeoCalib uncertainty of the references (QA:
    /// median 3.9–4.5°): asking for more precision than the reference has made tilt ping-pong.
    /// 12 Nov (Reynard: "tilt agak ketat, jangan terlalu"): 4/6 → 3/4.5 (25% tighter). A tilt that cannot get
    /// closer is still accepted at the limit after `stuckAfter`, so a tighter band cannot loop forever.
    var pitchEnter = 3.0, pitchExit = 4.5
    /// Room to a frame edge under which the reference pitch is not pushed further.
    var edgeRoom = 0.03
    /// 13 Nov (Reynard: full body "tilt ke atas langsung hancur, kaki kepotong"): full body stops a reference-
    /// pitch tilt earlier, while the feet still have this much room (frame units), to absorb overshoot.
    var edgeRoomFull = 0.07
    var topEnter = 0.05, topExit = 0.08
    /// Auto crop: the crop may run this far past the frame before tilt is asked for.
    var cropSlack = 0.02
    /// Auto crop (11 Nov): the crop would leave the frame sideways by more than this (frame width units)
    /// → "Move the phone left / right" (stops below `panExit`). Before, the crop was clamped silently and
    /// the person ended up nearer the centre than the reference.
    var panEnter = 0.05, panExit = 0.02
    /// 12 Nov (Reynard: "biar ga crop parah, suruh geser HP dikit"): the crop's centre is this far from the frame
    /// centre (frame width units) → turn the phone toward the person until within `panCentreExit`, so the crop
    /// stays near the middle of the sensor instead of cutting from one side. Accepted at the limit like pan.
    var panCentreEnter = 0.10, panCentreExit = 0.04

    // Distance aim (12 Nov, Reynard: "minimal 2 m, ijonya di 2,2 m"). While "Move back / closer" is shown,
    // it stops a margin INSIDE the band, not at its edge: distance × this (r ÷ this), so a small sway after
    // stopping does not fall out again. Only when the band is wide enough (Auto crop); No crop keeps its band.
    /// 12 Nov: 1.10 → 1.05 (Reynard: "2,1 aja"). Full body keeps more room: with the feet and head margins a
    /// person at r 0.95 barely fits, and a small tilt cut the feet (log 17:15: tilt down ↔ move back for 17 s).
    var distanceAim = 1.05
    var distanceAimFull = 1.12
    /// 13 Nov (Reynard: "3/4 butuh mundur sedikit juga"): 3/4 stops 10% inside (r 0.95 → 0.86).
    var distanceAimThreeQuarter = 1.10
    /// 13 Nov: full body cut at the start while the phone is within this many degrees of the reference pitch →
    /// "Move back" instead of "Tilt down/up" (the tilt phase would tilt back later and cut the feet again).
    var cutTiltBeyond = 10.0
    /// 13 Nov (Reynard: "full body harus agak rough, kalau nggak jelek"): Auto crop, full body only — the
    /// closest allowed size is lower than 0.95 so the feet and head always keep room (with aim ×1.12 the
    /// move back stops at r ≈ 0.79). Exit / reopen move down with it.
    var fullEnterHigh = 0.88, fullExitHigh = 0.93, fullReopenHigh = 1.0

    // At the limit (Reynard: "udah limit, kudu lebih fleksibel").
    /// A phone-height or tilt instruction that brought no progress for this long is accepted as the
    /// limit (the person cannot crouch / tilt further): the phase completes, logged "accepted at the limit".
    var stuckAfter: TimeInterval = 4.0
    /// Progress = the error shrank by at least this share of its best value.
    var stuckProgress = 0.15

    // Framing.
    /// Auto crop: straighten the horizon in the crop up to this roll, degrees (if the crop still fits).
    /// 12 Nov (Reynard): roll 0–2° straightened by the crop; 2–5° → "Straighten the phone" until ≤ `rollStop`;
    /// above `rollAskMax` left as it is (a deliberate Dutch angle). Was 3° crop-only, no instruction.
    var maxCropRoll = 2.0
    var rollStop = 1.5
    var rollAskMax = 5.0
    /// Log 17:15: a roll hovering at 1.9–2.1° flipped "ready" on and off. The ask starts only when the median
    /// roll (over `window`) passes `maxCropRoll + rollAskMargin`; the crop straightens up to `rollCropReach`.
    var rollAskMargin = 0.3
    var rollCropReach = 2.5
    /// No crop: horizontal offset accepted without comment (logged), frame units.
    var noCropCentreTolerance = 0.10

    /// Zoom: No crop takes 2× when the person at 1× is smaller than this share of the reference span.
    var twoXBelow = 0.6

    /// Crop floor (megapixels): never save a crop smaller than this.
    var cropFloorMegapixels = 12.0
    var depthCropFloorMegapixels = 8.0

    static let standard = PhasedParameters()

    /// Size band for a framing policy, given the crop's smallest linear scale (`cropMinScale`,
    /// e.g. 0.5 for 12 MP out of 48 MP).
    func sizeBand(_ policy: FramingPolicy, cropMinScale: Double) -> SizeBand {
        switch policy {
        case .noCrop:
            // No crop cannot fix the size later: aim close to the reference.
            return SizeBand(enterLow: 0.94, enterHigh: 1.06, exitLow: 0.90, exitHigh: 1.10,
                            reopenLow: 0.75, reopenHigh: 1.28)
        case .autoCrop:
            let c = min(max(cropMinScale, 0.3), 1)
            return SizeBand(enterLow: min(c * 1.2, 0.88), enterHigh: 0.95,
                            exitLow: min(c * 1.08, 0.84), exitHigh: 1.0,
                            // Below the exit band, always: with a 12 MP source (Blur On / depth) c ≈ 1
                            // gave reopen 0.97 > enter 0.88 → done ↔ reopen loop (log 16:59).
                            reopenLow: min(c * 0.98, min(c * 1.08, 0.84) * 0.94), reopenHigh: 1.08)
        }
    }

    func margins(_ shot: PhasedShot, _ policy: FramingPolicy) -> ShotMargins {
        switch (shot, policy) {
        case (.full, .autoCrop):         ShotMargins(top: 0.04, bottom: 0.05, side: 0.02)
        case (.full, .noCrop):           ShotMargins(top: 0.03, bottom: 0.03, side: 0.02)
        case (.threeQuarter, .autoCrop): ShotMargins(top: 0.04, bottom: 0.06, side: 0.02)
        case (.threeQuarter, .noCrop):   ShotMargins(top: 0.03, bottom: 0.0, side: 0.02)
        case (.half, .autoCrop):         ShotMargins(top: 0.04, bottom: 0.06, side: 0.02)
        case (.half, .noCrop):           ShotMargins(top: 0.03, bottom: 0.0, side: 0.02)
        }
    }

    /// For the log: every parameter that changes behaviour.
    var logSummary: String {
        String(format: "aim ×%.2f (3/4 ×%.2f full ×%.2f) · roll crop ≤%.1f ask ≤%.1f stop %.1f · ", distanceAim, distanceAimThreeQuarter, distanceAimFull, maxCropRoll, rollAskMax, rollStop)
        + String(format: "window %.1f quick %.1f reopenWin %.1f start %.1f complete %.1f reopen %.1f stale %.1f loss %.1f · vantage ±%.1f/±%.1f/±%.1f faces · pitch ±%.0f/±%.0f · top ±%.2f/±%.2f · 2× below %.2f · floor %.0f/%.0f MP · head eye %.2f face %.2f after %.1f s %@ · limit after %.1f s (< %.0f%% progress)",
               window, quickWindow, reopenWindow, startDwell, completeDwell, reopenDwell, staleAfter, lossGrace,
               vantageFacesEnter, vantageFacesExit, vantageFacesReopen, pitchEnter, pitchExit, topEnter, topExit,
               twoXBelow, cropFloorMegapixels, depthCropFloorMegapixels,
               PhasedMeasure.headEyeFraction, PhasedMeasure.headFaceRatio, headAfterFaceLoss, headFromPose ? "on" : "off",
               stuckAfter, stuckProgress * 100)
    }
}

// MARK: - Evidence over time

/// Values with their time; decisions read medians over a recent window (never a few frames).
nonisolated struct TimedSamples: Sendable, Equatable {
    private(set) var items: [(t: TimeInterval, v: Double)] = []
    var maxAge: TimeInterval = 3

    static func == (a: TimedSamples, b: TimedSamples) -> Bool {
        a.items.count == b.items.count && zip(a.items, b.items).allSatisfy { $0.t == $1.t && $0.v == $1.v }
    }

    mutating func append(_ v: Double, at t: TimeInterval) {
        guard v.isFinite else { return }
        items.append((t, v))
        items.removeAll { t - $0.t > maxAge }
    }

    mutating func removeAll() { items.removeAll() }

    func values(since t: TimeInterval) -> [Double] { items.filter { $0.t >= t }.map(\.v) }

    /// Median of the samples newer than `now − window`, when there are at least `minCount`.
    func median(now: TimeInterval, window: TimeInterval, minCount: Int) -> Double? {
        let v = values(since: now - window)
        guard v.count >= minCount else { return nil }
        return Self.median(v)
    }

    /// Time covered by the samples in the window.
    func coverage(now: TimeInterval, window: TimeInterval) -> TimeInterval {
        let recent = items.filter { $0.t >= now - window }
        guard let first = recent.first, let last = recent.last else { return 0 }
        return last.t - first.t
    }

    var newest: TimeInterval? { items.last?.t }

    static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        return v.count % 2 == 0 ? (v[v.count / 2 - 1] + v[v.count / 2]) / 2 : v[v.count / 2]
    }
}

/// How long a condition has held without a break.
nonisolated struct Dwell: Sendable, Equatable {
    private(set) var since: TimeInterval?

    /// Updates with this update's condition; returns how long it has held (0 when false).
    @discardableResult
    mutating func update(_ condition: Bool, now: TimeInterval) -> TimeInterval {
        if condition {
            let start = since ?? now
            since = start
            return now - start
        }
        since = nil
        return 0
    }

    mutating func reset() { since = nil }
}
