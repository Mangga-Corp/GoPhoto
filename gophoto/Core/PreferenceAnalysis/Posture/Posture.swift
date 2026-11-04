import Foundation

/// What the subject of a reference photo is doing with their body. Taxonomy reference:
/// `Docs/sitting-pose-classification.md` (only the parts that change the guide are used).
nonisolated enum Posture: String, Codable, Sendable, CaseIterable, Hashable {
    case standing
    case sitting
    /// No person, or a posture that is neither (lying, crouching…).
    case other
    /// Not enough evidence, or the evidence is ambiguous.
    case unknown
}
