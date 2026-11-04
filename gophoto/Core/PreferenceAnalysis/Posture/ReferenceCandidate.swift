import Foundation

/// What the selector needs to know about one reference photo.
nonisolated struct ReferenceCandidate: Equatable, Sendable {
    /// `PhotoItem.id.uuidString`.
    let photoID: String
    /// nil when the photo's framing was not read (it is then no reference at all).
    let shot: PresetAnalysis.ShotSize?
    /// nil for photos analysed before postures existed.
    let reading: PostureReading?
}
