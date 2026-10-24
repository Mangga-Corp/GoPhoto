import Foundation
import CoreGraphics

/// What the guided camera needs from one preset. Saved with the preset in `index.json`.
/// Built by `PreferenceAnalyzer` from the full analysis (`PreferenceProfile`).
nonisolated struct PresetAnalysis: Codable, Sendable, Equatable {
    /// Bump when a field changes meaning, so presets saved earlier are analysed again.
    static let currentVersion = 11

    var version: Int = PresetAnalysis.currentVersion
    var analyzedAt: Date
    var photoCount: Int
    /// Median box of the main person (normalised 0...1, origin top-left), the same basis as
    /// `PersonDetector` (full body). Nil when no photo had one usable person.
    var subjectBox: CGRect?
    /// Photos that contributed to `subjectBox`.
    var subjectPhotoCount: Int
    var angle: AngleTarget
    /// Photos per camera-angle category (`CameraAngleCategory.rawValue`), for the debug panel.
    var angleCounts: [String: Int]?
    /// Photos whose camera angle was determined.
    var angleDeterminedCount: Int?
    /// Weighted share of the leading angle category (0...1).
    var angleLeadingShare: Double?

    // Camera-height and distance guide (version 3). Optional so older saves still decode.

    /// Camera height relative to the eyes, degrees (+ = camera above the eyes): median over the
    /// photos of the majority angle, only values within ±45°. Nil without an angle majority.
    var eyeElevation: Double?
    /// Angular height of the face, degrees (face height in the image converted with GeoCalib's
    /// field of view), median over the photos that have it. Lens-independent distance cue.
    var headAngle: Double?
    /// Most photos have the person cut off at the top / bottom edge of the frame.
    var clippedTop: Bool?
    var clippedBottom: Bool?

    // Fixed rules (version 4), for guide mode E. Optional so older saves still decode.

    /// Majority framing: `FramingCategory.rawValue` ("fullBody" / "halfBody"). Nil without a majority.
    var framing: String?
    /// Majority camera height against the body: `CameraHeightLevel.rawValue`
    /// ("aboveHead", "eye", "shoulder", "hip", "knee", "ground"). Nil without a majority.
    var heightLevel: String?

    /// Angular height of the person's box, degrees (box height converted with GeoCalib's field of
    /// view), median over photos with a valid person. Lens-independent distance cue (version 5):
    /// a person photographed with 0.5x looks small in the frame but has the same angle at the
    /// same distance, so the camera no longer asks to stand twice as far.
    var bodyAngle: Double?

    // Eye side (version 6): the camera angle is one of two sides of the subject's eye line.

    /// `EyeSide.rawValue`: camera above or below the subject's eyes. Nil only when no photo was
    /// read and the framing is unknown (then the PRD fixed rule applies).
    var eyeSide: String?
    /// `EyeSideSource.rawValue`: where the side came from.
    var eyeSideSource: String?
    /// Mean chance (0...1) that a photo was taken from above the eyes, over the photos that voted.
    var eyeAboveShare: Double?
    /// Photos that voted: camera-vs-eyes angle read, same framing as the preset.
    var eyeSidePhotoCount: Int?

    /// The same analysis made from one framing's photos only, keyed by `FramingCategory.rawValue`
    /// ("fullBody" / "halfBody"); version 7. Present only for framings with at least one photo.
    var framingVariants: [String: PresetAnalysis]?
    /// Framing of each photo (`PhotoItem.id.uuidString` → `FramingCategory.rawValue`), so the
    /// preset's gallery can group them; version 7.
    var photoFramings: [String: String]?

    /// Where the half-body photos cut the body, from the skeleton (version 9): "chest" (shoulders
    /// in, hips out), "thigh" (hips in, knees out) or "shin" (knees in, ankles out). Majority over
    /// the half-body photos with a reading; nil without one.
    var cutLevel: String?
    /// Half-body photos that showed `cutLevel`, and those with any cut reading.
    var cutLevelCount: Int?
    var cutLevelOf: Int?

    /// Face height as a share of the frame height, median over the photos (version 10). The
    /// half-body distance step matches it: unlike `headAngle` it does not depend on the
    /// reference's lens (a 2× portrait would otherwise ask to stand twice as far).
    var faceHeight: Double?

    /// Half-body crop target (version 11), median over the half-body photos with a body pose:
    /// neck position (normalized, top-left), neck-to-hip length (frame heights), and where the
    /// frame's bottom cuts, in torso lengths below the hips (0.6 ≈ mid-thigh). Nil without them.
    var halfBodyNeck: CGPoint?
    var halfBodyTorso: Double?
    var cutBelowHip: Double?

    /// The analysis for the framing picked in the preset popover: that framing's variant, or this
    /// one when the preset has no photo of it (or nothing is picked).
    func forFraming(_ framing: String?) -> PresetAnalysis {
        guard let framing, let variant = framingVariants?[framing] else { return self }
        return variant
    }

    nonisolated enum EyeSide: String, Sendable {
        case above, below
    }

    nonisolated enum EyeSideSource: String, Sendable {
        /// The preset's photos agree on a side: their side, their angles (the user's taste).
        case taste
        /// The photos were read but split: side from the framing rule, angles from the photos
        /// (kept on that side of the eyes).
        case mixed
        /// Too few photos read: framing rule (full body → below, half body → above), eye level.
        case `default`
    }

    nonisolated enum AngleTarget: Codable, Sendable, Equatable {
        /// At least 60% of the photos share one camera angle: match this phone pitch.
        /// `pitchDown` uses the `DeviceTilt` convention (positive = phone tilted down).
        case match(category: String, pitchDown: Double)
        /// Angles were read but none holds a majority (or only beyond ±45°): no angle guidance.
        case noGuidance
        /// No photo's angle could be read: PRD fixed rule, keep the phone straight.
        case fixedRule
    }

    var isCurrent: Bool { version == Self.currentVersion }
}
