import Foundation

/// What a seated subject sits on (spec: chair_sitting / floor_sitting / elevated_surface_sitting).
nonisolated enum SupportSurface: String, Codable, Sendable, CaseIterable, Hashable {
    case chair
    case floor
    /// Bench, stairs, ledge, table edge…
    case elevated
    case unknown
}
