import Foundation
import CoreGraphics

/// What the guided camera needs from one preset. Saved with the preset in `index.json`.
/// Built by `PreferenceAnalyzer` from the full analysis (`PreferenceProfile`).
nonisolated struct PresetAnalysis: Codable, Sendable, Equatable {
    /// Bump when a field changes meaning, so presets saved earlier are analysed again.
    static let currentVersion = 2

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
