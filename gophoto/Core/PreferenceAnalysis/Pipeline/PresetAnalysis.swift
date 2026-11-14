import Foundation
import CoreGraphics

/// What the guided camera needs from one preset. Saved with the preset in `index.json`.
/// Built by `PreferenceAnalyzer` from the full analysis (`PreferenceProfile`).
nonisolated struct PresetAnalysis: Codable, Sendable, Equatable {
    /// Bump when a field changes meaning, so presets saved earlier are analysed again.
    static let currentVersion = 18

    var version: Int = PresetAnalysis.currentVersion
    var analyzedAt: Date
    var photoCount: Int
    /// The reference photos this analysis was made from (`PhotoItem.id.uuidString`): photos
    /// without a person are left out before the analysis. Nil in analyses saved before the
    /// person check (they used every photo) and in custom preferences.
    var analyzedPhotoIDs: [String]?
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

    // Anchor side (version 16), shot variants only: the photos vote camera above / below one body
    // anchor (full body → knee, three-quarter → chest, half body → eyes); the winning side's
    // biggest shooting style makes `eyeElevation` and the tilt. Nil when the vote was not used.

    /// `AnchorSide.Anchor.rawValue` ("knee" / "chest" / "eye").
    var anchorReference: String? = nil
    /// Photos that voted above / below the anchor.
    var anchorAbove: Int? = nil
    var anchorBelow: Int? = nil
    /// Shooting styles on the winning side (1 = not split) and the photos the target came from.
    var anchorStyleCount: Int? = nil
    var anchorTargetPhotoCount: Int? = nil
    /// Cross-check of `eyeElevation`: mean over the same photos weighted by 1/σ² (debug panel).
    var eyeElevationWeighted: Double? = nil

    /// Camera height vs the eyes in face heights (version 17): median over the same photos as
    /// `eyeElevation`, + = camera above the eyes. The guide's height step uses it instead of the
    /// angle: walking closer or farther changes the angle but not this. Nil = no face read.
    var eyeOffsetFaces: Double? = nil

    /// Vantage target as a range + confidence (12 Nov, display only; the guide still uses
    /// `eyeOffsetFaces`). Optional, decoded if present; version unchanged (no field changed meaning).
    /// Face heights, + = camera above the eyes. Older presets need a Rescan to fill it.
    var vantageRange: VantageRange? = nil

    nonisolated struct VantageRange: Codable, Sendable, Equatable {
        /// Photos that shaped the range / left out because their σ was too large.
        var used = 0, excluded = 0
        /// agree / varied / twoGroups / uncertain
        var kind = "uncertain"
        /// high / low
        var confidence = "low"
        var low: Double? = nil, high: Double? = nil
        /// twoGroups only: [[low, high], [low, high]].
        var groups: [[Double]]? = nil
        /// 1/σ²-weighted centre, sample spread, median σ, largest neighbour gap in σ units.
        var center = 0.0, spread = 0.0, medianSigma = 0.0, gapZ = 0.0
    }

    /// How blurred the references' backgrounds are (version 18): median of background / person
    /// sharpness (`BackgroundBlurMeter`), ~1 = sharp background, ~0.2 = strong bokeh. The blur
    /// copy is rendered to match it. Nil = no photo could be measured.
    var backgroundBlur: Double? = nil
    /// Photos the median came from.
    var backgroundBlurCount: Int? = nil

    /// Sets `backgroundBlur` here and in every variant, each from its own photos.
    mutating func applyBackgroundBlur(_ ratios: [String: Double]) {
        func median(_ ids: [String]) -> (Double, Int)? {
            let v = ids.compactMap { ratios[$0] }.sorted()
            guard !v.isEmpty else { return nil }
            return ((v[(v.count - 1) / 2] + v[v.count / 2]) / 2, v.count)
        }
        let all = median(Array(ratios.keys))
        backgroundBlur = all?.0
        backgroundBlurCount = all?.1
        for key in (shotVariants ?? [:]).keys {
            let ids = (photoShotSizes ?? [:]).filter { $0.value == key && photoPostures?[$0.key] != BodyPosture.sitting.rawValue }.keys.map { $0 }
            let m = median(ids)
            shotVariants?[key]?.backgroundBlur = m?.0
            shotVariants?[key]?.backgroundBlurCount = m?.1
        }
        for key in (framingVariants ?? [:]).keys {
            let m = median((photoFramings ?? [:]).filter { $0.value == key }.keys.map { $0 })
            framingVariants?[key]?.backgroundBlur = m?.0
            framingVariants?[key]?.backgroundBlurCount = m?.1
        }
        for key in (postureVariants ?? [:]).keys {
            let m = median((photoPostures ?? [:]).filter { $0.value == key }.keys.map { $0 })
            postureVariants?[key]?.backgroundBlur = m?.0
            postureVariants?[key]?.backgroundBlurCount = m?.1
        }
    }

    /// The same analysis made from one framing's photos only, keyed by `FramingCategory.rawValue`
    /// ("fullBody" / "halfBody"); version 7. Present only for framings with at least one photo.
    var framingVariants: [String: PresetAnalysis]?
    /// Framing of each photo (`PhotoItem.id.uuidString` → `FramingCategory.rawValue`), so the
    /// preset's gallery can group them; version 7.
    var photoFramings: [String: String]?
    /// Shot size of each photo (`PhotoItem.id.uuidString` → `ShotSize.rawValue`), for the
    /// gallery's four sections; version 12. Data only: the guide still uses full / half body.
    var photoShotSizes: [String: String]?
    /// The same analysis made from one shot size's photos only, keyed by `ShotSize.rawValue`;
    /// version 13. Present only for shot sizes with at least one photo: the preset popover offers
    /// exactly these, and the camera guides with the picked one.
    var shotVariants: [String: PresetAnalysis]?
    /// In a shot variant: its `ShotSize.rawValue` (debug panel).
    var shotSize: String?

    /// The same analysis made from the seated full-body photos only, keyed by
    /// `BodyPosture.rawValue` ("sitting"); version 15. Seated full-body photos are left out of
    /// `shotVariants`, which are the standing shot sizes the camera offers a standing person.
    /// Sitting is only read with the legs visible, so a seated person only gets full body.
    var postureVariants: [String: PresetAnalysis]?
    /// Posture of each photo whose posture was read (`PhotoItem.id.uuidString` → `BodyPosture.rawValue`).
    var photoPostures: [String: String]?

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

    /// How bright the reference photos are (version 14): median mean luminance, 0...1. Whole
    /// preset only (not in the framing / shot variants). Personalises the lighting tips.
    var lightLevel: Double?

    /// What every evidence source did over the photos, so a failed analysis (a required Vision
    /// request could not run) is not saved like one that found nobody. Whole preset only. Nil in
    /// analyses saved before it existed: unknown, not failed (see `usability`). Optional and
    /// decoded if present, so older saves still decode; the version is unchanged because no
    /// existing field changed meaning.
    var evidence: AnalysisEvidenceSummary?

    /// The analysis made from this shot size's photos only, or nil when the preset has none.
    /// No fallback: `PhotoSessionConfiguration.resolve` decides which shot size the camera uses.
    func shotVariant(_ shot: ShotSize) -> PresetAnalysis? {
        shotVariants?[shot.rawValue]
    }

    /// The analysis made from the seated full-body photos, or nil when the preset has none.
    var sittingVariant: PresetAnalysis? { postureVariants?[BodyPosture.sitting.rawValue] }

    /// Whether the camera can guide this shot size: a standing variant, or for full body the
    /// seated one (a preset of seated photos only).
    func hasGuide(for shot: ShotSize) -> Bool {
        shotVariant(shot) != nil || (shot == .full && sittingVariant != nil)
    }

    /// Shot sizes the camera offers for a person in this posture, widest first:
    /// - sitting: full body only (a seated body can't be read when cut above the knees);
    /// - standing or not read yet: the standing shot sizes this preset has photos of (a preset of
    ///   seated photos only still offers full body).
    func shotOptions(for posture: BodyPosture?) -> [ShotSize] {
        if posture == .sitting { return [.full] }
        let standing = availableShots
        return standing.isEmpty && sittingVariant != nil ? [.full] : standing
    }

    /// The analysis that guides `shot` for a person in `posture`.
    /// Sitting: the seated photos' analysis, else the standing full body adjusted to a seated
    /// height (`seatedEstimate`), else nil (no preset target). Standing: that shot size's variant,
    /// else the seated one (a preset of seated photos only).
    func guide(for shot: ShotSize, posture: BodyPosture?) -> PresetAnalysis? {
        if posture == .sitting {
            return sittingVariant ?? shotVariant(.full)?.seatedEstimate()
        }
        return shotVariant(shot) ?? (shot == .full ? sittingVariant : nil)
    }

    /// Seated person's box is about this share of their standing box's height.
    static let seatedHeightRatio = 0.72

    /// A standing full-body analysis adapted to a seated person, for presets without seated photos:
    /// the person box is shorter (same bottom, same centre) so the distance guide doesn't ask to
    /// come closer until a seated person is as tall in the frame as a standing one.
    func seatedEstimate() -> PresetAnalysis {
        var seated = self
        if let box = subjectBox {
            let height = box.height * Self.seatedHeightRatio
            seated.subjectBox = CGRect(x: box.minX, y: box.maxY - height, width: box.width, height: height)
        }
        seated.bodyAngle = bodyAngle.map { $0 * Self.seatedHeightRatio }
        return seated
    }

    /// Shot sizes this preset has photos of, widest first.
    var availableShots: [ShotSize] {
        ShotSize.allCases.filter { shotVariants?[$0.rawValue] != nil }
    }

    /// The shot size with the most photos (ties: the wider one), or nil without any.
    var defaultShot: ShotSize? {
        var best: (shot: ShotSize, count: Int)?
        for shot in availableShots {               // widest first: a tie keeps the wider one
            let count = shotVariants?[shot.rawValue]?.photoCount ?? 0
            if best == nil || count > best!.count { best = (shot, count) }
        }
        return best?.shot
    }

    /// How much of the body a photo shows, by where the frame's bottom cuts it (headshot types):
    /// full body; three-quarter (mid-thigh or knees up); half body (waist up); one-quarter (chest up).
    nonisolated enum ShotSize: String, Sendable, CaseIterable {
        case full, threeQuarter, half, quarter

        var title: String {
            switch self {
            case .full: "Full body"
            case .threeQuarter: "Three-quarter"
            case .half: "Half body"
            case .quarter: "One-quarter"
            }
        }

        /// Label of the camera's shot size picker (above the shutter).
        var pickerTitle: String {
            switch self {
            case .full: "Full body"
            case .threeQuarter: "3/4"
            case .half: "Half body"
            case .quarter: "1/4"
            }
        }

        /// Short label for the preset popover's switch.
        var shortTitle: String {
            switch self {
            case .full: "Full"
            case .threeQuarter: "3/4"
            case .half: "Half"
            case .quarter: "1/4"
            }
        }

        /// The coarse framing the guide's rules use: full body, or cut at the bottom.
        var framing: FramingCategory { self == .full ? .fullBody : .halfBody }
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
