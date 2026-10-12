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

    // Position: allowed distance between centres (fraction of the photo)
    static let positionEnter: CGFloat = 0.06
    static let positionExit: CGFloat = 0.09
    // Size: allowed difference between person height and target height (fraction)
    static let sizeEnter: CGFloat = 0.15
    static let sizeExit: CGFloat = 0.22

    /// How the person's box compares to this target.
    func offset(of personBox: CGRect) -> FramingOffset {
        FramingOffset(dx: personBox.midX - rect.midX,
                      dy: personBox.midY - rect.midY,
                      sizeRatio: personBox.height / rect.height)
    }
}

/// + dx = person RIGHT of target, + dy = person BELOW target, sizeRatio > 1 = person too BIG.
nonisolated struct FramingOffset: Equatable, Sendable {
    let dx: CGFloat
    let dy: CGFloat
    let sizeRatio: CGFloat
}

// MARK: - Presets (prototype)

extension FramingTarget {
    /// Person on the left third, vertically centred.
    static let ruleOfThirdsLeft = FramingTarget(
        rect: CGRect(x: 0.18, y: 0.20, width: 0.30, height: 0.60)
    )

    /// Person in the middle. Neutral placeholder until the AI provides a target.
    static let center = FramingTarget(
        rect: CGRect(x: 0.35, y: 0.20, width: 0.30, height: 0.60)
    )
}
