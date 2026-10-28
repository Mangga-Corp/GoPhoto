//
//  LensRecommendationEngine.swift
//  gophoto
//
//  Deterministic lens recommendation logic.
//

import CoreGraphics
import Foundation
import AVFoundation

/// A single lens recommendation with explanation and caution.
struct LensRecommendation: Equatable, Sendable {
    let option: LensOption
    let reason: String
    let caution: String?
    let currentZoom: Double
    let isAutomatic: Bool
    let evidence: [String]

    var title: String { option.title }
    var recommendedZoom: Double { option.zoomFactor }
}

/// Evidence gathered for one recommendation pass.
struct RecommendationEvidence: Sendable {
    let personBox: CGRect?
    let face: CGRect?
    let target: FramingTarget
    let guideMode: GuideMode
    let evaluation: GuideEvaluation
    let verticalFOV: Double?
    let isPhoneStill: Bool
    let subjectClippedTop: Bool
    let subjectClippedBottom: Bool
    let subjectClippedLeft: Bool
    let subjectClippedRight: Bool
    let capabilities: LensCapabilities
    let exposure: ExposureSnapshot?
    let appliedZoom: Double
    let activeConstituent: AVCaptureDevice.DeviceType?
}

/// A continuous zoom target with explanation and confidence.
struct ZoomTarget: Equatable, Sendable {
    let targetZoom: Double
    let reason: String
    let confidence: Double   // 0…1, how reliable the evidence is

    var isSignificant: Bool { confidence >= 0.5 }
}

/// The recommendation engine. Pure logic; no UI, no sensors.
nonisolated enum LensRecommendationEngine {

    // MARK: - Public

    /// Produce a recommendation for the current evidence, or nil if none is warranted.
    static func recommend(_ evidence: RecommendationEvidence) -> LensRecommendation? {
        let caps = evidence.capabilities

        // Precedence:
        // 1. Invalid camera state → no recommendation.
        // 2. Severe framing problem (clipped subject) → wider view.
        // 3. No strong evidence → no change.

        guard !caps.currentZoom.isNaN, caps.currentZoom > 0 else {
            LensRecommendationLog.evaluation(
                zoom: caps.currentZoom, minZoom: caps.minZoom, maxZoom: caps.maxZoom,
                iso: evidence.exposure?.iso, exposureDuration: evidence.exposure?.exposureDuration,
                exposureTargetOffset: evidence.exposure?.exposureTargetOffset,
                activeCamera: evidence.activeConstituent, personDetected: evidence.personBox != nil,
                clipped: false, lowLight: evidence.exposure?.isLikelyLowLight,
                telephotoEligible: false, recommendation: nil,
                reason: "invalid_zoom"
            )
            return nil
        }
        guard let person = evidence.personBox else {
            LensRecommendationLog.evaluation(
                zoom: caps.currentZoom, minZoom: caps.minZoom, maxZoom: caps.maxZoom,
                iso: evidence.exposure?.iso, exposureDuration: evidence.exposure?.exposureDuration,
                exposureTargetOffset: evidence.exposure?.exposureTargetOffset,
                activeCamera: evidence.activeConstituent, personDetected: false,
                clipped: false, lowLight: evidence.exposure?.isLikelyLowLight,
                telephotoEligible: false, recommendation: nil,
                reason: "no_person"
            )
            return nil
        }

        let clipped = evidence.subjectClippedTop || evidence.subjectClippedBottom ||
        evidence.subjectClippedLeft || evidence.subjectClippedRight

        // Rule 1: clipped subject → wider.
        if clipped {
            LensRecommendationLog.evaluation(
                zoom: caps.currentZoom, minZoom: caps.minZoom, maxZoom: caps.maxZoom,
                iso: evidence.exposure?.iso, exposureDuration: evidence.exposure?.exposureDuration,
                exposureTargetOffset: evidence.exposure?.exposureTargetOffset,
                activeCamera: evidence.activeConstituent, personDetected: true,
                clipped: true, lowLight: evidence.exposure?.isLikelyLowLight,
                telephotoEligible: false, recommendation: nil,
                reason: "evaluating_clipped"
            )
            let rec = widerRecommendation(for: evidence)
            if let rec {
                LensRecommendationLog.decision(
                    recommendation: rec.title,
                    autoApply: rec.isAutomatic,
                    reason: rec.reason,
                    evidence: rec.evidence
                )
            }
            return rec
        }

        LensRecommendationLog.evaluation(
            zoom: caps.currentZoom, minZoom: caps.minZoom, maxZoom: caps.maxZoom,
            iso: evidence.exposure?.iso, exposureDuration: evidence.exposure?.exposureDuration,
            exposureTargetOffset: evidence.exposure?.exposureTargetOffset,
            activeCamera: evidence.activeConstituent, personDetected: true,
            clipped: false, lowLight: evidence.exposure?.isLikelyLowLight,
            telephotoEligible: false, recommendation: nil,
            reason: "no_strong_evidence"
        )
        return nil
    }

    // MARK: - Automatic 1× ↔ 0.5× switching

    /// What the framing evidence asks of the lens right now (before the stability / cooldown gates).
    enum AutoLensWish: Equatable {
        case ultrawide(Double)
        case wide
        /// No change: unreliable evidence, inside the hysteresis band, or a zoom the feature doesn't manage.
        case hold
    }

    /// The decision and why (for the diagnostic log).
    struct AutoLensDecision: Equatable {
        let wish: AutoLensWish
        let reason: String
    }

    /// Composition evidence for the automatic switch. All parts are optional: a missing part holds.
    struct AutoLensContext {
        /// Left/right clutter of a live frame at the current zoom, nil when not measured or stale.
        var clutter: EdgeClutterMetrics?
        /// The preset's majority `ProminenceBand.rawValue`, nil when the references gave none.
        var environmentProminence: String?
        /// Typical object share of the references' surroundings, nil when unknown.
        var preferredObjectShare: Double?
    }

    /// Switch to 0.5× when the person would be this many times the target height at 1×.
    /// At 1.5 the 0.5× view (0.75 of target) is clearly closer to the target than 1× (1.5).
    static let autoSwitchRatio = 1.5
    /// Return to 1× only when the person would be at most this many times the target height at 1×.
    /// At 1.2 the 1× view (1.2) is closer to the target than 0.5× (0.6). The gap to 1.5 is the hysteresis.
    static let autoReturnRatio = 1.2
    /// A person cut at both the top and the bottom of the frame counts as this tall (frame heights),
    /// and then switches at the lower `autoOverflowRatio`, still above the 4/3 break-even where 0.5×
    /// starts to fit the target better than 1× (so presets taller than about 0.8 never switch).
    static let autoOverflowHeight = 1.1
    static let autoOverflowRatio = 1.375
    /// Busy surroundings need stronger size evidence before 0.5× is chosen: below this ratio they
    /// keep 1×. A subject cut off by the frame ignores it.
    static let autoClutterSwitchRatio = 1.8
    /// With busy surroundings the return to 1× is allowed up to this ratio (above `autoReturnRatio`,
    /// below `autoSwitchRatio`, so it never re-triggers the switch back).
    static let autoClutterReturnRatio = 1.3
    /// At 1× the subject must be at most this tall (frame heights) to count as fitting.
    static let autoFitHeight = 0.95
    /// Margin kept inside the 1× crop around the subject, frame fraction.
    static let autoCropMargin = 0.03
    /// Fallbacks as a person height (frame fraction at 1×) when the preset has no usable subject box.
    static let autoFallbackSwitchHeight = 0.96
    static let autoFallbackReturnHeight = 0.80

    /// Decides whether the subject is too large for the intended composition at 1×.
    /// - `referenceHeight`: the preset's subject-box height, or nil when none is reliable.
    /// Size is judged by the person's height scaled to what it would be at 1× (it is proportional to
    /// zoom), so the answer does not change when the lens changes and cannot oscillate by itself.
    /// A person merely touching a side/top edge is not "too large"; without a preset target the
    /// fallback also needs the box to span the full frame height.
    ///
    /// Composition (`context`) refines the size rule; it never starts a switch on its own:
    /// - At 1×, in the band just above the switch ratio (subject large, not cut off), busy
    ///   left/right surroundings keep 1× (the wider view would add more clutter), and clean ones
    ///   allow 0.5×. A subject cut off at the frame edges switches regardless: 1× would crop it.
    /// - At 0.5×, a subject that still fits a 1× view (inside the central crop, not cut off, close
    ///   to the target size) returns to 1× when the content the wide view adds is busy, unless the
    ///   preset's references show the environment as the main part of the picture (or that is
    ///   unknown): the 1× crop would remove important context.
    /// - Missing or unreliable clutter evidence holds the current lens.
    static func autoLens(personBox: CGRect?, referenceHeight: Double?, capabilities caps: LensCapabilities,
                         context: AutoLensContext = AutoLensContext()) -> AutoLensDecision {
        func hold(_ reason: String) -> AutoLensDecision { AutoLensDecision(wish: .hold, reason: reason) }
        guard let box = personBox, box.height >= 0.05, caps.currentZoom.isFinite, caps.currentZoom > 0
        else { return hold("no_reliable_person") }
        // Vision cannot report a box taller than the frame, so a too-close person is under-measured.
        // A box cut at both the top and the bottom of the frame means the person overflows it: its
        // height is at least the frame's, and the box height alone would never reach the ratio.
        let spansFrame = box.minY <= 0.02 && box.maxY >= 0.98
        var heightAtWide = Double(box.height) / caps.currentZoom
        if spansFrame { heightAtWide = max(heightAtWide, autoOverflowHeight / caps.currentZoom) }
        let reference = referenceHeight.flatMap { (0.15...0.95).contains($0) ? $0 : nil }
        let switchHeight = reference.map { $0 * (spansFrame ? autoOverflowRatio : autoSwitchRatio) }
            ?? autoFallbackSwitchHeight
        let returnHeight = reference.map { $0 * autoReturnRatio } ?? autoFallbackReturnHeight

        if caps.currentZoom >= 0.95 {
            guard let ultrawide = caps.bestUltrawide, ultrawide < 0.95 else { return hold("no_ultrawide") }
            guard heightAtWide >= switchHeight else { return hold("subject_fits") }
            guard reference != nil || spansFrame else { return hold("fallback_needs_overflow") }
            if let reference, !spansFrame, heightAtWide < reference * autoClutterSwitchRatio {
                // Large, but not cut off and not far past the target: the surroundings decide.
                guard let clutter = context.clutter, clutter.isReliable else { return hold("awaiting_clutter") }
                if clutter.isSubstantial(preferredObjectShare: context.preferredObjectShare) {
                    return hold("clutter_veto")
                }
                return AutoLensDecision(wish: .ultrawide(ultrawide), reason: "subject_large_clean_edges")
            }
            return AutoLensDecision(wish: .ultrawide(ultrawide),
                                    reason: spansFrame ? "subject_overflows_frame" : "subject_far_too_large")
        }
        guard let ultrawide = caps.bestUltrawide, caps.currentZoom <= ultrawide + 0.05 else {
            return hold("zoom_not_managed")
        }
        if heightAtWide <= returnHeight { return AutoLensDecision(wish: .wide, reason: "subject_fits_at_1x") }

        // Clutter-aware return: only when the subject is close to the target size at 1×, is not cut
        // off by the 1× crop, and the preset does not value the environment around the subject.
        if let reference, heightAtWide <= reference * autoClutterReturnRatio, heightAtWide <= autoFitHeight,
           fitsWideViewCrop(box, zoom: caps.currentZoom) {
            guard let prominence = context.environmentProminence else { return hold("preference_unknown") }
            if prominence == "environmentDominates" { return hold("context_important") }
            guard let clutter = context.clutter, clutter.isReliable else { return hold("awaiting_clutter") }
            if clutter.isSubstantial(preferredObjectShare: context.preferredObjectShare) {
                return AutoLensDecision(wish: .wide, reason: "wide_edges_cluttered")
            }
            return hold("edges_clean")
        }
        return hold("hold_ultrawide")
    }

    /// The subject (box in the current frame) stays inside the part of it a 1× view would keep.
    private static func fitsWideViewCrop(_ box: CGRect, zoom: Double) -> Bool {
        EdgeClutter.wideViewCrop(zoom: zoom).insetBy(dx: autoCropMargin, dy: autoCropMargin).contains(box)
    }

    // MARK: - Continuous zoom target (0.5× – 3.0×)

    /// Computes a continuous zoom target from the current framing evidence. Returns nil when the
    /// evidence is too unreliable or the current zoom is already inside the deadband.
    ///
    /// The target is derived from the ratio of the desired person-frame fraction (from preset
    /// analysis) to the current person-frame fraction, then refined by clutter and environmental
    /// preferences. All work is done in user-perceived zoom space, which is linear for both
    /// digital zoom and virtual multi-camera breakpoints.
    static func computeZoomTarget(
        personBox: CGRect?,
        referenceHeight: Double?,     // PresetAnalysis.subjectBox.height (frame fraction, ~1×)
        faceHeight: Double?,          // PresetAnalysis.faceHeight (frame fraction at 1×, zoom-independent)
        bodyAngle: Double?,           // PresetAnalysis.bodyAngle (degrees, angular size)
        currentZoom: Double,
        verticalFOV: Double?,         // current vertical FOV at current zoom
        baseVerticalFOV: Double?,     // vertical FOV at zoom 1.0
        capabilities: LensCapabilities,
        clutter: EdgeClutterMetrics?,
        environmentProminence: String?,
        preferredObjectShare: Double?,
        isPhoneStill: Bool
    ) -> ZoomTarget? {
        // 1. Validate inputs.
        guard let box = personBox, box.height >= 0.05,
              currentZoom.isFinite, currentZoom > 0,
              capabilities.minZoom < capabilities.maxZoom else {
            return ZoomTarget(targetZoom: currentZoom, reason: "no_reliable_person", confidence: 0)
        }

        let currentFraction = box.height

        // 2. Desired frame fraction at zoom 1.0.
        let desiredAt1x: Double? = {
            // faceHeight is explicitly zoom-independent (see PresetAnalysis).
            if let fh = faceHeight, fh > 0 && fh < 1 { return fh }
            // subjectBox.height is the median reference box; treat as ~1× with a sanity clamp.
            if let rh = referenceHeight, rh > 0.1 && rh < 0.95 { return rh }
            // Fallback: derive from bodyAngle and base FOV.
            if let angle = bodyAngle, angle > 0, angle < 90,
               let baseFov = baseVerticalFOV, baseFov > 0, baseFov < 180 {
                let halfAngle = angle * .pi / 360
                let halfFov = baseFov * .pi / 360
                return 2 * atan(tan(halfAngle) / tan(halfFov))
            }
            return nil
        }()

        guard let desired = desiredAt1x, desired > 0 else {
            return ZoomTarget(targetZoom: currentZoom, reason: "no_size_reference", confidence: 0)
        }

        // 3. Raw size-based target: frame fraction scales linearly with user zoom.
        //    At zoom Z the person fills desired * Z of the frame; currently they fill currentFraction.
        //    targetZoom = currentZoom * desired / currentFraction.
        var rawTarget = currentZoom * desired / currentFraction

        // 4. Clutter and environment refinement.
        let clutterFactor: Double = {
            guard let cl = clutter, cl.isReliable else { return 1.0 }
            let isBusy = cl.isSubstantial(preferredObjectShare: preferredObjectShare)
            switch environmentProminence {
            case "environmentDominates":
                return isBusy ? 0.90 : 0.95   // zoom out slightly to keep context
            case "subjectDominates":
                return isBusy ? 1.15 : 1.0    // zoom in to cut clutter
            default:
                return isBusy ? 1.10 : 0.95   // balanced: lean toward clean edges
            }
        }()
        rawTarget *= clutterFactor

        // 5. Clamp to supported range.
        let clamped = max(capabilities.minZoom, min(capabilities.maxZoom, rawTarget))

        // 6. Confidence.
        var confidence = 0.0
        confidence += 0.35  // reliable person box
        if faceHeight != nil || referenceHeight != nil { confidence += 0.30 }
        if isPhoneStill { confidence += 0.20 }
        if clutter?.isReliable == true { confidence += 0.15 }
        return ZoomTarget(targetZoom: clamped, reason: "size_and_clutter", confidence: min(confidence, 1.0))
    }

    // MARK: - Rule 1: Wider

    private static func widerRecommendation(for evidence: RecommendationEvidence) -> LensRecommendation? {
        let caps = evidence.capabilities
        guard let zoom = caps.bestUltrawide, zoom < caps.currentZoom - 0.05 else { return nil }

        let reason: String
        if evidence.subjectClippedTop || evidence.subjectClippedBottom {
            reason = "The person is close to the frame edge. A wider view fits more of the subject into the frame."
        } else {
            reason = "The person is near the side edge of the frame. A wider view keeps them from being cut off."
        }

        let caution = "People near the edges may appear stretched with an ultrawide view."

        return LensRecommendation(
            option: .ultrawide(zoom),
            reason: reason,
            caution: caution,
            currentZoom: caps.currentZoom,
            isAutomatic: false,
            evidence: ["clipped", "ultrawideAvailable"]
        )
    }
}
