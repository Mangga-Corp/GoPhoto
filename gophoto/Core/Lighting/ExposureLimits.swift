//
//  ExposureLimits.swift
//  gophoto
//
//  Core layer: exposure limits the lighting rules share, so they cannot drift apart.
//

import Foundation

nonisolated enum ExposureLimits {
    /// The slowest shutter worth using with a person in the frame (spec X1 / "A2"), seconds:
    /// slower blurs a moving person. Guidance in the lighting rules.
    static let slowestShutter: TimeInterval = 1.0 / 60
}
