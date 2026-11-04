import Foundation

/// One classified attribute with the two numbers the spec asks for on every classification.
/// `unknown` values mean "visible but ambiguous"; an attribute that does not apply at all
/// (for example leg configuration of a standing person) is `nil` in its container instead.
nonisolated struct ClassifiedAttribute<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    let value: Value
    /// 0...1.
    let confidence: Double
    let visibility: AttributeVisibility

    /// May this attribute be used as a reference? Below the confidence threshold or out of
    /// sight it may not (`ReferenceThresholds`).
    var isUsable: Bool {
        confidence >= ReferenceThresholds.minConfidence && visibility != .notVisible
    }
}
