//
//  LinePhoneRig.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

import RealityKit
import UIKit
import simd

@MainActor
final class LinePhoneRig {
    private let phone = PhoneRig()

    var root: Entity {
        phone.root
    }

    init() {}

    func apply(_ pose: PhonePose) {
        phone.apply(pose)
    }

    func setOpacity(_ value: Double) {
        phone.setOpacity(value)
    }
}
