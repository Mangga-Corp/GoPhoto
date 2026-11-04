import Foundation

/// The reference photos for one requested framing × posture, by tier (photo IDs).
nonisolated struct ReferencePartition: Equatable, Sendable {
    var exact: [String] = []
    var samePosture: [String] = []
    var sameFraming: [String] = []
}
