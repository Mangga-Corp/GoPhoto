import Foundation

/// The deterministic fallback for "framing F, posture P" (pure functions, no UI, no models).
///
/// Tiers, best first: `exact` (F + P), `samePosture` (P, other framing), `sameFraming`
/// (F, other posture), `combined` (the last two together), `default` (rules only).
///
/// A photo's posture is only believed when its posture attribute is usable
/// (`ClassifiedAttribute.isUsable`: confidence ≥ `ReferenceThresholds.minConfidence`, not
/// `notVisible`) and is standing or sitting. A photo whose posture cannot be believed is NOT a
/// posture reference, but still carries its composition, so it can serve `sameFraming`.
/// Exception, for compatibility: before postures existed every photo was treated as standing,
/// so an unbelieved posture still counts as standing when standing is requested.
nonisolated enum ReferenceSelector {

    /// The posture a photo can be trusted to show, or nil.
    static func believedPosture(_ reading: PostureReading?) -> Posture? {
        guard let reading, reading.posture.isUsable else { return nil }
        switch reading.posture.value {
        case .standing, .sitting: return reading.posture.value
        case .other, .unknown: return nil
        }
    }

    /// Does this photo count as a `posture` reference?
    static func counts(_ candidate: ReferenceCandidate, as posture: Posture) -> Bool {
        let believed = believedPosture(candidate.reading)
        return believed == posture || (posture == .standing && believed == nil)
    }

    static func partition(_ candidates: [ReferenceCandidate], shot: PresetAnalysis.ShotSize,
                          posture: Posture) -> ReferencePartition {
        var result = ReferencePartition()
        for candidate in candidates {
            guard let candidateShot = candidate.shot else { continue }
            let samePosture = counts(candidate, as: posture)
            if candidateShot == shot, samePosture { result.exact.append(candidate.photoID) }
            else if samePosture { result.samePosture.append(candidate.photoID) }
            else if candidateShot == shot { result.sameFraming.append(candidate.photoID) }
        }
        return result
    }

    static func level(hasExact: Bool, hasSamePosture: Bool, hasSameFraming: Bool) -> ReferenceMatchLevel {
        if hasExact { return .exact }
        switch (hasSamePosture, hasSameFraming) {
        case (true, true): return .combined
        case (true, false): return .samePosture
        case (false, true): return .sameFraming
        case (false, false): return .default
        }
    }

    static func level(of partition: ReferencePartition) -> ReferenceMatchLevel {
        level(hasExact: !partition.exact.isEmpty, hasSamePosture: !partition.samePosture.isEmpty,
              hasSameFraming: !partition.sameFraming.isEmpty)
    }

    /// Key of a stored analysis variant: `<tier>:<shot>:<posture>`.
    static func variantKey(_ tier: ReferenceMatchLevel, shot: PresetAnalysis.ShotSize, posture: Posture) -> String {
        "\(tier.rawValue):\(shot.rawValue):\(posture.rawValue)"
    }
}
