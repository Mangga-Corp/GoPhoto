//
//  PhoneSceneView.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import SwiftUI
import RealityKit

/// Cheap to create on every SwiftUI refresh; builds the heavy rig only once, on first use.
@MainActor
final class PhoneRigHolder {
    lazy var rig = PhoneRig()
}

struct PhoneSceneView: View {
    var pose: PhonePose
    /// Distance of the camera from the phone, metres. Later parts pass a larger value
    /// when the phone needs room to move.
    var cameraDistance: Float = 0.45

    @State private var holder = PhoneRigHolder()

    var body: some View {
        RealityView { content in
            content.camera = .virtual

            let rig = holder.rig
            rig.root.removeFromParent()
            content.add(rig.root)
            for light in PhoneLighting.makeLights() { content.add(light) }

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.position = SIMD3<Float>(0, 0, cameraDistance)      // looks down -Z, at the phone
            content.add(camera)

            rig.apply(pose)
        } update: { _ in
            holder.rig.apply(pose)
        }
        .background(Color.clear)
        .accessibilityHidden(true)   // decorative here; Part 6 adds real accessibility
    }
}
