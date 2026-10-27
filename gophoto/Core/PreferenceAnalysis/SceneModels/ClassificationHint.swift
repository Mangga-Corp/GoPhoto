import Foundation

/// One classifier guess, e.g. ("seashore, coast, seacoast", 0.62).
/// Kept for the `ImageClassifying` protocol; GoPhoto does not run a classifier.
nonisolated struct ClassificationHint: Sendable, Equatable {
    let label: String
    let confidence: Double
}
