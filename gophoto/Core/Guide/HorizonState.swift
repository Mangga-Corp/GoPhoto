//
//  HorizonState.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 12/10/26.
//
import Foundation

/// What the horizon line should show. Pure logic: no sensors, no UI.
nonisolated enum HorizonState: Equatable, Sendable {
    case hidden                       // flat phone, or tilted on purpose (> 10°)
    case tilted(degrees: Double)      // signed: + = phone rotated clockwise
    case level                        // straight → yellow, then fades

    static let levelEnter: Double = 0.5   // become level below this
    static let levelExit: Double = 1.5    // stay level until above this (no flicker)
    static let maxShown: Double = 10      // hide beyond this
    static let maxPitch: Double = 75      // phone close to flat → hide

    /// Next state from the current tilt. `current` is used to avoid flicker around 0°.
    static func next(roll: Double, pitch: Double, current: HorizonState) -> HorizonState {
        guard abs(pitch) <= maxPitch else { return .hidden }

        let size = abs(roll)
        if size > maxShown { return .hidden }

        let levelLimit = current == .level ? levelExit : levelEnter
        if size < levelLimit { return .level }

        return .tilted(degrees: (roll * 10).rounded() / 10)   // 0.1° steps
    }

    /// Signed tilt for drawing (0 when hidden or level).
    var roll: Double {
        if case .tilted(let degrees) = self { return degrees }
        return 0
    }
}
