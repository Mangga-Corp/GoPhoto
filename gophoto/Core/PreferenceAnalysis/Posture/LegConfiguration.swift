import Foundation

/// Coarse leg shape of a seated subject. The spec's "Leg-Extended Variants" are leg
/// configurations, not pose variants, so they live here. Finer values (`legsApart`,
/// `oneKneeRaised`, `figureFour`…) can be added later.
nonisolated enum LegConfiguration: String, Codable, Sendable, CaseIterable, Hashable {
    case extended
    case bent
    case crossed
    case unknown
}
