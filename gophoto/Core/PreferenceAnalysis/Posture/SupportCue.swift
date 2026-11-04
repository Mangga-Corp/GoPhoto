import Foundation

/// Evidence from the segmentation that a seat is next to the subject.
nonisolated struct SupportCue: Sendable, Equatable {
    let surface: SupportSurface
    /// Share (0...1) of the band around the subject that the seat's region fills.
    let share: Double

    /// DETR labels that are a seat. Chairs and sofas are chairs; the rest are raised surfaces.
    private static let chairLabels: Set<String> = ["chair", "couch", "sofa"]
    private static let elevatedLabels: Set<String> = ["bench", "stairs", "table", "dining table", "counter", "bed"]

    /// Seat cues from the environment regions of one photo (reuses the existing DETR result).
    static func cues(from regions: [SemanticRegion]) -> [SupportCue] {
        regions.compactMap { region in
            guard region.isValid, region.reliability.isEligible,
                  let relation = region.subjectRelation else { return nil }
            let labels = Set(([region.family.key] + region.rawLabels.map(\.label))
                .compactMap { SegmentationTaxonomy.familyKey(forLabel: $0) })
            if !labels.isDisjoint(with: chairLabels) { return SupportCue(surface: .chair, share: relation.ringShare) }
            if !labels.isDisjoint(with: elevatedLabels) { return SupportCue(surface: .elevated, share: relation.ringShare) }
            return nil
        }
    }
}
