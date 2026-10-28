//
//  ExposureLimits.swift
//  gophoto
//
//  Core layer: exposure limits the lighting rules share, so they cannot drift apart.
//

import Foundation

nonisolated enum ExposureLimits {
    /// The slowest shutter the app ever allows with a person in the frame (spec X1 / "A2"); the low-light rule uses it, seconds.
    /// Anything dimmer is made up with ISO.
    static let slowestShutter: TimeInterval = 1.0 / 60
}
