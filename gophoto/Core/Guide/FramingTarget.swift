//
//  FramingTarget.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 11/10/26.
//
//
//  FramingTarget.swift
//  gophoto
//
//  Where the person SHOULD be in the photo.
//  Today: a hard-coded preset. Later: produced by the AI from the user's preferences.
//

import CoreGraphics

nonisolated struct FramingTarget: Equatable, Sendable {
    /// Normalized 0...1, origin TOP-LEFT, in photo coordinates.
    let rect: CGRect

    /// True when the person's box centre is close enough to the target's centre (position only).
    func isAligned(with personRect: CGRect, tolerance: CGFloat) -> Bool {
        abs(personRect.midX - rect.midX) <= tolerance &&
        abs(personRect.midY - rect.midY) <= tolerance
    }
}

// MARK: - Presets (prototype)

extension FramingTarget {
    /// Person on the left third, vertically centred.
    static let ruleOfThirdsLeft = FramingTarget(
        rect: CGRect(x: 0.18, y: 0.20, width: 0.30, height: 0.60)
    )
    static let center = FramingTarget(
        rect: CGRect(x: 0.35, y: 0.20, width: 0.30, height: 0.60)
    )
}
