import Foundation

/// Which way the torso faces the camera. Only `frontFacing`, `threeQuarterFacing` and
/// `sideFacing` are produced for now (from the shoulder span); the other spec values are
/// listed so they can be added without changing stored data.
nonisolated enum TorsoOrientation: String, Codable, Sendable, CaseIterable, Hashable {
    case frontFacing
    case threeQuarterFacing
    case sideFacing
    case backFacing
    case twistedTorso
    case unknown
}
