//
//  HeightGuidanceRig.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import RealityKit
import UIKit
import simd

@MainActor
final class HeightGuidanceRig {
    /// How far the phone travels, metres.
    static let travelMeters: Float = 0.07

    let root = Entity()
    private let phone = PhoneRig()

    init() {
        root.name = "HeightGuidanceRig"
        root.addChild(phone.root)
    }

    func update(frame: HeightFrame, direction: Direction,
                yawDegrees: Double, guideColor: UIColor = .white) {
        phone.apply(PhonePose(yawDegrees: yawDegrees, tiltUpDegrees: 0,
                              liftMeters: lift(for: frame.progress, direction: direction)))
        phone.setOpacity(frame.phoneOpacity)
    }

    // MARK: - Private

    /// Phone height: starts at neutral (0), travels in the instructed direction (+travel for up, -travel for down),
    /// then returns smoothly to neutral.
    private func lift(for progress: Double, direction: Direction) -> Double {
        let p = min(max(progress, 0), 1)
        return direction.sign * Double(Self.travelMeters) * p
    }
}
