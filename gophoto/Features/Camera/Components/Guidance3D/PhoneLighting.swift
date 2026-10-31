//
//  PhoneLighting.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import RealityKit
import UIKit

@MainActor
enum PhoneLighting {
    static func makeLights() -> [Entity] {
        [
            // Key: soft white from upper-left — clean, even studio lighting for mockup
            light("Key", color: UIColor(white: 1.0, alpha: 1), intensity: 2800, from: SIMD3<Float>(-0.40, 0.50, 0.60)),
            // Fill: slightly cooler, from the right — softens shadows
            light("Fill", color: UIColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 1), intensity: 1800, from: SIMD3<Float>(0.50, 0.15, 0.45)),
            // Rim: gentle backlight — subtle edge definition without harsh highlights
            light("Rim", color: UIColor(white: 1.0, alpha: 1), intensity: 1600, from: SIMD3<Float>(0.30, 0.40, -0.55)),
            // Bottom fill: lifts shadows underneath for that floating mockup feel
            light("BottomFill", color: UIColor(red: 0.90, green: 0.92, blue: 0.96, alpha: 1), intensity: 1200, from: SIMD3<Float>(0, -0.45, 0.35)),
        ]
    }

    private static func light(_ name: String, color: UIColor, intensity: Float, from position: SIMD3<Float>) -> Entity {
        let entity = DirectionalLight()
        entity.name = name
        entity.light.color = color
        entity.light.intensity = intensity
        entity.look(at: .zero, from: position, relativeTo: nil)
        return entity
    }
}
