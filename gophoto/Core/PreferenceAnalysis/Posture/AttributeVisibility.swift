import Foundation

/// How much of the body part behind an attribute can be seen (spec: visible / partially_visible /
/// not_visible).
nonisolated enum AttributeVisibility: String, Codable, Sendable, CaseIterable, Hashable {
    case visible
    case partiallyVisible
    case notVisible

    /// The weaker of two: an attribute that needs two body parts is as visible as the worse one.
    func weaker(than other: AttributeVisibility) -> AttributeVisibility {
        let order: [AttributeVisibility] = [.visible, .partiallyVisible, .notVisible]
        return order.firstIndex(of: self)! >= order.firstIndex(of: other)! ? self : other
    }
}
