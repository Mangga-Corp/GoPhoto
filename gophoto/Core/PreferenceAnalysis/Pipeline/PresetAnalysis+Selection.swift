import Foundation
import CoreGraphics

/// The framing × posture pick (`forSelection`) on top of the stored analyses.
extension PresetAnalysis {

    /// The photos as the selector sees them, rebuilt from what was saved.
    nonisolated var referenceCandidates: [ReferenceCandidate] {
        (photoShotSizes ?? [:]).map { id, raw in
            ReferenceCandidate(photoID: id, shot: ShotSize(rawValue: raw), reading: photoPostures?[id])
        }
    }

    /// How well this preset's photos match `shot` × `posture`.
    nonisolated func matchLevel(shot: ShotSize, posture: Posture) -> ReferenceMatchLevel {
        ReferenceSelector.level(of: ReferenceSelector.partition(referenceCandidates, shot: shot, posture: posture))
    }

    /// The analysis the guide uses for a shot size and posture, with `matchLevel`, `posture` and
    /// `sources` filled in.
    ///
    /// - Standing (or no shot size): exactly the old `forFraming` result, only labelled. Nothing
    ///   about standing guidance changes.
    /// - Sitting: the seated variants are merged by tier (`ReferenceSelector`). Composition and
    ///   camera angle come from the same-framing photos (transferable); pose style comes from the
    ///   same-posture photos; camera height and size for a seated full body come from
    ///   `SittingFullBodyDefaults` unless a seated full-body photo exists.
    nonisolated func forSelection(shot: String?, posture: Posture) -> PresetAnalysis {
        guard let shot, let size = ShotSize(rawValue: shot) else {
            var legacy = forFraming(shot)
            legacy.posture = posture.rawValue
            return legacy
        }
        let level = matchLevel(shot: size, posture: posture)
        guard posture == .sitting else {
            var legacy = forFraming(shot)
            legacy.posture = posture.rawValue
            legacy.matchLevel = level.rawValue
            return legacy
        }

        func variant(_ tier: ReferenceMatchLevel) -> PresetAnalysis? {
            selectionVariants?[ReferenceSelector.variantKey(tier, shot: size, posture: .sitting)]
        }
        let poseSource = variant(.samePosture)
        var result: PresetAnalysis
        switch level {
        case .exact:       result = variant(.exact) ?? self
        case .sameFraming, .combined: result = variant(.sameFraming) ?? self
        case .samePosture, .default:  result = self
        }
        result.framingVariants = nil
        result.shotVariants = nil
        result.selectionVariants = nil
        result.photoPostures = nil
        result.photoFramings = nil
        result.photoShotSizes = nil
        result.framing = size.framing.rawValue
        result.shotSize = size.rawValue
        result.posture = Posture.sitting.rawValue
        result.matchLevel = level.rawValue

        let usesPoseTier = level == .samePosture || level == .combined
        if usesPoseTier {
            result.sittingSupport = poseSource?.sittingSupport
            result.sittingLegs = poseSource?.sittingLegs
        }
        var sources = ["composition": "default", "pose": "default", "cameraHeight": "default"]
        switch level {
        case .exact:
            sources = sources.mapValues { _ in "exact" }
        case .sameFraming:
            sources["composition"] = "sameFraming"
        case .samePosture:
            sources["pose"] = "samePosture"
        case .combined:
            sources["composition"] = "sameFraming"
            sources["pose"] = "samePosture"
        case .default:
            break
        }
        result.sources = sources

        // Seated full body without a seated full-body photo: the rules for a seated subject.
        if size == .full, level != .exact {
            applySittingDefaults(to: &result, hasFramingSource: level == .sameFraming || level == .combined)
        }
        return result
    }

    /// `SittingFullBodyDefaults` over an analysis that was not learned from seated full-body photos.
    private nonisolated func applySittingDefaults(to analysis: inout PresetAnalysis, hasFramingSource: Bool) {
        let support = analysis.sittingSupport.flatMap(SupportSurface.init(rawValue:))
        // Size: the standing full-body box shrunk to a seated height. Without full-body photos
        // there is no size to learn, so a default box is used.
        let base = hasFramingSource ? (analysis.subjectBox ?? SittingFullBodyDefaults.standingBox)
                                    : SittingFullBodyDefaults.standingBox
        analysis.subjectBox = PostureTargets.seatedBox(from: base, support: support)
        analysis.bodyAngle = hasFramingSource
            ? analysis.bodyAngle.map { $0 * PostureTargets.seatedHeightRatio(support: support) } : nil
        analysis.clippedTop = false
        analysis.clippedBottom = false

        // Camera: a little below the eyes, never a high angle. Height is posture-specific, so a
        // standing photo's height is only kept inside the allowed range.
        let elevation = hasFramingSource ? (analysis.eyeElevation ?? SittingFullBodyDefaults.eyeElevation)
                                         : SittingFullBodyDefaults.eyeElevation
        let range = SittingFullBodyDefaults.elevationRange
        analysis.eyeElevation = min(range.upperBound, max(range.lowerBound, elevation))
        analysis.eyeSide = EyeSide.below.rawValue
        analysis.eyeSideSource = EyeSideSource.default.rawValue
        analysis.heightLevel = nil   // the guide's fallback for full body: between chest and waist
        var pitch = 0.0
        if hasFramingSource, case .match(_, let learned) = analysis.angle { pitch = learned }
        analysis.angle = .match(category: EyeSide.below.rawValue,
                                pitchDown: min(pitch, SittingFullBodyDefaults.maxPitchDown))
    }

    /// The honest one-liner for the popover, or nil when the photos match exactly.
    nonisolated static func matchNote(level: ReferenceMatchLevel, shot: ShotSize, posture: Posture) -> String? {
        let word = posture == .sitting ? "seated" : "standing"
        let size = shot.title.lowercased()
        let missing = "No \(word) \(size) photo in this preference yet. "
        switch level {
        case .exact: return nil
        case .samePosture: return missing + "Using your \(word) photos for pose, and general tips for framing."
        case .sameFraming: return missing + "Using your \(size) photos for framing, and general tips for pose."
        case .combined: return missing + "Combining your \(word) photos (pose) with your \(size) photos (framing)."
        case .default: return missing + "Using general \(word) \(size) tips."
        }
    }
}
