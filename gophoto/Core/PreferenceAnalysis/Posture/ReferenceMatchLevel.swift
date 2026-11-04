import Foundation

/// How well the preference's photos match the requested framing × posture.
nonisolated enum ReferenceMatchLevel: String, Codable, Sendable, CaseIterable, Hashable {
    /// A photo with this framing and this posture.
    case exact
    /// This posture at another framing (pose style, expression, torso direction).
    case samePosture
    /// This framing with another posture (composition, camera angle, background, mood, colour).
    case sameFraming
    /// Both of the above.
    case combined
    /// Nothing usable: general best-practice rules for this posture and framing.
    case `default`
}
