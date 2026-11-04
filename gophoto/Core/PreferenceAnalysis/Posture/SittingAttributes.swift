import Foundation

/// The seated-only attributes that change what the guide asks for. Present only when the
/// posture is `sitting`. Other spec attributes (pose variant, torso lean, arm position) are
/// not read yet.
nonisolated struct SittingAttributes: Codable, Equatable, Sendable {
    var supportSurface: ClassifiedAttribute<SupportSurface>
    var legConfiguration: ClassifiedAttribute<LegConfiguration>
}
