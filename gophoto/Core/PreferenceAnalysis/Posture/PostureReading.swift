import Foundation

/// The posture analysis of one reference photo.
nonisolated struct PostureReading: Codable, Equatable, Sendable {
    var posture: ClassifiedAttribute<Posture>
    /// Transferable between postures and framings (the body turn stays when the pose changes).
    var torsoOrientation: ClassifiedAttribute<TorsoOrientation>
    /// nil unless `posture` is `sitting` (not applicable).
    var sitting: SittingAttributes?

    static let unreadable = PostureReading(
        posture: .init(value: .unknown, confidence: 0, visibility: .notVisible),
        torsoOrientation: .init(value: .unknown, confidence: 0, visibility: .notVisible),
        sitting: nil)
}
