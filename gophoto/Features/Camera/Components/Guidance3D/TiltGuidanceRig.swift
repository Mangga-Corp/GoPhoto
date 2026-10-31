//
//  TiltGuidanceRig.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

import RealityKit
import UIKit
import simd

@MainActor
final class TiltGuidanceRig {
    let root = Entity()
    private let phone = PhoneRig()

    init() {
        root.name = "TiltGuidanceRig"
        root.addChild(phone.root)
    }

    /// - Parameters:
    ///   - degrees: swing size; sanitized with the same rules as `GuidanceMotion`.
    ///   - yawDegrees: how the phone is seen (`TiltView.yawDegrees`).
    func update(frame: TiltFrame, direction: Direction, degrees: Double,
                yawDegrees: Double, guideColor: UIColor = .white) {
        let swing = GuidanceMotion.tiltDegrees(forPitchError: degrees)

        // Konvensi arah dari tengah:
        // Saat mengarahkan lebih ke atas (.up)   -> kamera belakang naik ke atas (target positif)
        // Saat mengarahkan lebih ke bawah (.down) -> kamera belakang turun ke bawah (target negatif)
        let target = (direction == .up) ? swing : -swing

        let progress = min(max(frame.progress, 0), 1)
        phone.apply(PhonePose(yawDegrees: yawDegrees, tiltUpDegrees: target * progress, liftMeters: 0))
        phone.setOpacity(frame.phoneOpacity)
    }
}
