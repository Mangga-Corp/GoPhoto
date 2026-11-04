import Foundation
import CoreGraphics

/// Best-practice rules for a seated, full-body photo. They are the baseline when the
/// preference has no seated full-body photo to learn from (`PresetAnalysis.forSelection`).
///
/// Measurable rules feed `GuideFlow` (camera low, not a high angle; legs inside the frame;
/// a smaller body box). The rest cannot be measured live, so `tips` shows them on the phone-
/// height card.
nonisolated enum SittingFullBodyDefaults {

    /// Camera a little below the eyes (chest / waist of a seated subject), degrees.
    static let eyeElevation = -6.0
    /// The elevation target never goes outside this range, even when the standing photos
    /// it was learned from say otherwise (degrees, + = camera above the eyes).
    static let elevationRange = -12.0 ... -2.0
    /// Phone pitch (+ = tilted down) never above this: no high angle that shortens the legs.
    static let maxPitchDown = 5.0

    /// A standing full-body box (head to toe with margin), used when no photo gives a full-body
    /// size; it is shrunk to a seated height by `PostureTargets.seatedBox`.
    static let standingBox = CGRect(x: 0.30, y: 0.08, width: 0.40, height: 0.84)

    /// Rules the guide cannot measure, in the order they matter.
    static let tips = [
        "Keep their legs and shoes fully in the frame",
        "Step back and zoom a little instead of going close with a wide lens",
        "Turn their body 3/4 to the camera, back straight, near the seat edge",
        "Extend one leg diagonally or cross the ankles; keep shoe soles away from the camera",
        "Leave headroom, and space in the direction they face"
    ]
}
