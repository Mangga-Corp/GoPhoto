import Foundation
import CoreGraphics

/// What the guided camera needs from one preset. Saved with the preset in `index.json`.
/// Built by `PreferenceAnalyzer` from the full analysis (`PreferenceProfile`).
nonisolated struct PresetAnalysis: Codable, Sendable, Equatable {
    /// Bump when a field changes meaning, so presets saved earlier are analysed again.
    static let currentVersion = 5

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
