//
//  TiltGuidanceView.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

import SwiftUI
import RealityKit

@MainActor
final class TiltDriver {
    lazy var rig = TiltGuidanceRig()

    var direction: Direction = .up
    var degrees = GuidanceMotion.tiltFallbackDegrees
    var tiltView: TiltView = .frontFacing
    var isActive = true {
        didSet {
            if isActive && !oldValue {
                elapsed = 0
            }
        }
    }
    var showsStillPose = false
    var speed = 1.0
    var guideColor: UIColor = .white
    /// Keeps the scene-event subscription alive.
    var keepAlive: [Any] = []

    private var elapsed: Double = 0

    func advance(by deltaTime: Double) {
        if isActive, deltaTime.isFinite {
            elapsed += min(max(deltaTime, 0), 0.1) * speed
            elapsed = elapsed.truncatingRemainder(dividingBy: TiltTimeline.period)
        }
        render()
    }

    func render() {
        let frame = showsStillPose ? TiltTimeline.stillFrame : TiltTimeline.frame(atTime: elapsed)
        rig.update(frame: frame, direction: direction, degrees: degrees,
                   yawDegrees: tiltView.yawDegrees, guideColor: guideColor)
    }
}

struct TiltGuidanceView: View {
    var direction: Direction
    /// Swing size in degrees (sanitized: 12...40, fallback 25).
    var degrees: Double = GuidanceMotion.tiltFallbackDegrees
    /// How the phone is seen: front, left 45°, or an angle from data.
    var tiltView: TiltView = .frontFacing
    /// False pauses the animation.
    var isActive: Bool = true
    /// Playback speed, 1 = normal.
    var speed: Double = 1
    var guideColor: UIColor = .white
    var cameraDistance: Float = 0.50
    /// Reduce Motion: show the upright phone with ghost and hinge, nothing moves.
    var showsStillPose: Bool = false

    @State private var driver = TiltDriver()

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
        driver.degrees = degrees
        driver.tiltView = tiltView
        driver.isActive = isActive
        driver.showsStillPose = showsStillPose
        driver.speed = speed
        driver.guideColor = guideColor
    }
}
