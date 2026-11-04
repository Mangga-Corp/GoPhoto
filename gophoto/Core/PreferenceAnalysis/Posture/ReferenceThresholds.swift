import Foundation

/// Tunable limits for using a classified attribute as a reference.
nonisolated enum ReferenceThresholds {
    /// Attributes below this confidence are not used as a reference.
    static let minConfidence = 0.6
}
