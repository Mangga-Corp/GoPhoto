//
//  HeightGuidanceView.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import SwiftUI
import RealityKit

@MainActor
final class HeightDriver {
    lazy var rig = HeightGuidanceRig()

    var direction: Direction = .up
    var isActive = true {
        didSet {
            if isActive && !oldValue {
                elapsed = 0
            }
        }
    }
    var showsStillPose = false
    var speed = 1.0
    var yawDegrees = 0.0
    var guideColor: UIColor = .white
    /// Keeps the scene-event subscription alive.
    var keepAlive: [Any] = []

    private var elapsed: Double = 0

    func advance(by deltaTime: Double) {
        if isActive, deltaTime.isFinite {
            elapsed += min(max(deltaTime, 0), 0.1) * speed
            elapsed = elapsed.truncatingRemainder(dividingBy: HeightTimeline.period)
        }
        render()
    }

    func render() {
        let frame = showsStillPose ? HeightTimeline.stillFrame : HeightTimeline.frame(atTime: elapsed)
        rig.update(frame: frame, direction: direction,
                   yawDegrees: yawDegrees, guideColor: guideColor)
    }
}

struct HeightGuidanceView: View {
    var direction: Direction
    /// False pauses the animation.
    var isActive: Bool = true
    /// Playback speed, 1 = normal.
    var speed: Double = 1
    /// 0 = flat front view as in the sketch; a little yaw shows off the 3D.
    var yawDegrees: Double = 0
    var guideColor: UIColor = .white
    /// Larger than a single pose needs because the phone has room to travel.
    var cameraDistance: Float = 0.58
    /// Reduce Motion: show the start pose with ghost and arrows, nothing moves.
    var showsStillPose: Bool = false

    @State private var driver = HeightDriver()

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            configureDriver()

            let rig = driver.rig
            rig.root.removeFromParent()
            content.add(rig.root)

            for light in PhoneLighting.makeLights() {
                content.add(light)
            }

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 30
            camera.position = SIMD3<Float>(0, 0, cameraDistance)
            content.add(camera)

            driver.render()

            let subscription = content.subscribe(to: SceneEvents.Update.self) { event in
                let deltaTime = event.deltaTime
                MainActor.assumeIsolated { driver.advance(by: deltaTime) }
            }
            driver.keepAlive.append(subscription)
        } update: { _ in
            configureDriver()
            driver.render()
        }
        .background(Color.clear)
        .accessibilityHidden(true)
    }

    private func configureDriver() {
        driver.direction = direction
        driver.isActive = isActive
        driver.showsStillPose = showsStillPose
        driver.speed = speed
        driver.yawDegrees = yawDegrees
        driver.guideColor = guideColor
    }
}
