import CoreGraphics
import Foundation

// MARK: - Adaptive FOV Evaluator

/// Deterministic, pure evaluator for realtime scene-aware adaptive field-of-view.
///
/// The evaluator decides whether the live camera should narrow, hold, or widen
/// its field of view based on the current subject bounding box, the preset's
/// framing target, and the device's zoom capabilities.
///
/// It mirrors GuideFlow's framing logic so that automatic zoom never contradicts
/// the existing photographer instructions. See the phase report for the exact
/// relationship between tolerances.
nonisolated enum AdaptiveFOV: Sendable {

    static let maximumAutomaticZoom = 2.0
    /// Zoom every camera session starts at, and returns to when nobody is detected.
    static let baselineZoom = 1.0

    /// Tighter than GuideFlow's `sizeEnter` (0.15) so adaptive FOV acts before the
    /// guide would ask the photographer to move closer or farther away.
    /// 10%: Vision's person box wobbles about ±5% frame to frame; 5% made the zoom chase it.
    static let deadband: CGFloat = 0.10
    /// Zooming out because the subject touches an edge: this much per step, not all the way out
    /// (all the way out, then in again until the edge, made the zoom ping-pong).
    static let edgeStep = 1.12
    /// Room kept between the subject and an edge the references leave free, when zooming in.
    static let edgeRoom: CGFloat = 0.03

    // MARK: - Input

    struct Input: Sendable {
        let personBox: CGRect
        let face: CGRect?
        let targetRect: CGRect
        let currentZoom: Double
        let minZoom: Double
        let maxZoom: Double
        let framing: String?            // "fullBody", "halfBody", or nil
        let targetFaceHeight: Double?   // used when framing == "halfBody"
        let clippedTop: Bool
        let clippedBottom: Bool
        let distanceFactor: Double      // from GuideMode (0.85 for heightFirstCrop, else 1.0)
        let environment: LiveEnvironmentSignal?
        let preserveEnvironmentContext: Bool
        let now: TimeInterval
        /// Shot size and the joints the live pose sees: the body-cut rule (`GuideFlow.cutGuard`)
        /// decides first, the same rule the guide uses, so zoom and guide never pull apart.
        var shotSize: PresetAnalysis.ShotSize? = nil
        var visibleJoints: Set<BodyJoint>? = nil
        /// Zoom the body cut needed (e.g. zoomed in until the feet left the frame): size alone
        /// may not zoom out past it, or the cut breaks again and the zoom ping-pongs.
        var cutFloorZoom: Double? = nil
    }

    /// Reasons that come from the body-cut rule start with this.
    static let cutReasonPrefix = "cut: "

    // MARK: - Output

    enum Decision: Equatable, Sendable {
        /// Zoom in to make the subject appear larger.
        case narrow(targetZoom: Double, reason: String)
        /// Keep the current field of view.
        case hold(reason: String)
        /// Zoom out to make the subject appear smaller or show more scene.
        case widen(targetZoom: Double, reason: String)
    }

    // MARK: - Evaluation

    static func evaluate(_ input: Input) -> Decision {
        guard input.targetRect.height > 0,
              input.currentZoom > 0,
              input.minZoom > 0,
              input.maxZoom >= input.minZoom else {
            return .hold(reason: "invalid inputs")
        }
        let effectiveMaxZoom = min(input.maxZoom, maximumAutomaticZoom)
        guard effectiveMaxZoom >= input.minZoom else {
            return .hold(reason: "device minimum exceeds automatic zoom limit")
        }

        // Edge-cutoff guard: if the preset's reference photos are NOT cut off at an edge
        // but the live person is, the zoom should widen to give more room.
        let refTop = input.clippedTop, refBottom = input.clippedBottom
        if (!refTop && input.personBox.minY <= GuideFlow.edgeMargin) ||
           (!refBottom && input.personBox.maxY >= 1 - GuideFlow.edgeMargin) {
            let target = max(input.minZoom, input.currentZoom / edgeStep)
            return .widen(targetZoom: target, reason: "subject cut off at frame edge")
        }

        // Body cut first (same rule as the guide): e.g. three-quarter with the feet in frame →
        // zoom in a step, whatever the size says.
        if let shot = input.shotSize, let joints = input.visibleJoints,
           let cut = GuideFlow.cutGuard(shot: shot, joints: joints,
                                        bottomCut: input.personBox.maxY >= 1 - GuideFlow.edgeMargin) {
            if cut.instruction == .moveCloser {
                let target = min(effectiveMaxZoom, input.currentZoom * edgeStep)
                return target > input.currentZoom * 1.01
                    ? .narrow(targetZoom: target, reason: cutReasonPrefix + cut.reason)
                    : .hold(reason: "\(cut.reason) · zoom at its limit")
            } else if cut.instruction == .moveFarther {
                let target = max(input.minZoom, input.currentZoom / edgeStep)
                return target < input.currentZoom * 0.99
                    ? .widen(targetZoom: target, reason: cutReasonPrefix + cut.reason)
                    : .hold(reason: "\(cut.reason) · zoom at its limit")
            }
        }

        let sizeRatio: CGFloat
        let source: String

        // Half-body with bottom cut-off: the box height is "head to frame edge", not
        // the person's real size, so the face's share of the frame sets the distance.
        if input.framing == "halfBody", input.clippedBottom,
           let face = input.face, face.height >= GuideFlow.minFaceHeight,
           let targetFace = input.targetFaceHeight, targetFace > 0 {
            sizeRatio = face.height / CGFloat(targetFace)
            source = "face size (half body)"
        } else {
            sizeRatio = input.personBox.height / input.targetRect.height
            source = "body size"
        }

        let factor = CGFloat(input.distanceFactor)
        let adjusted = sizeRatio / factor

        if adjusted > 1 + deadband {
            let rawTarget = input.currentZoom / Double(adjusted)
            let floor = max(input.minZoom, input.cutFloorZoom ?? input.minZoom)
            let target = max(floor, min(effectiveMaxZoom, rawTarget))
            if target >= input.currentZoom * 0.99 {
                return .hold(reason: "\(source) too large, but the body cut needs this zoom")
            }
            return .widen(targetZoom: target, reason: "\(source) too large")
        } else if adjusted < 1 - deadband {
            let rawTarget = input.currentZoom / Double(adjusted)
            var target = max(input.minZoom, min(effectiveMaxZoom, rawTarget))
            // Never zoom in so far that an edge the references leave free gets cut (zoom scales
            // the box about the frame centre): that would only trigger the edge guard above.
            var room = CGFloat.infinity
            if !refBottom, input.personBox.maxY > 0.5 {
                room = min(room, (0.5 - edgeRoom) / (input.personBox.maxY - 0.5))
            }
            if !refTop, input.personBox.minY < 0.5 {
                room = min(room, (0.5 - edgeRoom) / (0.5 - input.personBox.minY))
            }
            if room.isFinite { target = min(target, input.currentZoom * Double(room)) }
            if target <= input.currentZoom * 1.01 {
                return .hold(reason: "zooming in would cut the subject")
            }
            if input.preserveEnvironmentContext,
               let environment = input.environment,
               environment.isReliable(at: input.now),
               let removed = environment.removedEnvironmentFraction(
                    for: target / input.currentZoom),
               removed >= LiveEnvironmentSignal.minimumRemovedContextFraction {
                return .hold(reason: "zoom would remove preferred environmental context")
            }
            return .narrow(targetZoom: target, reason: "\(source) too small")
        } else {
            return .hold(reason: "framing within deadband")
        }
    }
}
