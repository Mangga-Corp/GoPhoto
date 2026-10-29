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

    /// Tighter than GuideFlow's `sizeEnter` (0.15) so adaptive FOV acts before the
    /// guide would ask the photographer to move closer or farther away.
    static let deadband: CGFloat = 0.05

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
    }

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
            return .widen(targetZoom: input.minZoom, reason: "subject cut off at frame edge")
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
            let target = max(input.minZoom, min(effectiveMaxZoom, rawTarget))
            return .widen(targetZoom: target, reason: "\(source) too large")
        } else if adjusted < 1 - deadband {
            let rawTarget = input.currentZoom / Double(adjusted)
            let target = max(input.minZoom, min(effectiveMaxZoom, rawTarget))
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
