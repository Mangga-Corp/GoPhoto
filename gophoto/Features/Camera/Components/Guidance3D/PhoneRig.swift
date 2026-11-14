//
//  PhoneRig.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import RealityKit
import UIKit
import simd

enum PhoneDimensions {
    // iPhone 17 proportions (metres)
    static let width: Float = 0.0715        // 71.5 mm
    static let height: Float = 0.1496       // 149.6 mm
    static let depth: Float = 0.0083        // 8.25 mm
    static let cornerRadius: Float = 0.0105 // 10.5 mm
    static let bevel: Float = 0.0014        // 1.4 mm contoured edges
}

@MainActor
final class PhoneRig {
    let root = Entity()
    private let yawNode = Entity()
    private let pivot = Entity()
    private let body = Entity()

    init() {
        root.name = "IPhoneMockupRig"
        root.addChild(yawNode)
        yawNode.addChild(pivot)

        // Pivot centered at the phone's geometric center (0, 0, 0)
        // so tilt and yaw motions rotate naturally in place.
        pivot.position = SIMD3<Float>(0, 0, 0)
        pivot.addChild(body)
        body.position = SIMD3<Float>(0, 0, 0)

        buildPhone(into: body)
        apply(.front)
    }

    func apply(_ pose: PhonePose) {
        let p = pose.sanitized
        let toRadians = Float.pi / 180
        root.position = SIMD3<Float>(0, Float(p.liftMeters), 0)
        yawNode.orientation = simd_quatf(angle: Float(p.yawDegrees) * toRadians, axis: SIMD3<Float>(0, 1, 0))
        // Rotasi tilt di sumbu X: angle positif membuat kamera belakang naik ke atas (tilt up)
        pivot.orientation = simd_quatf(angle: Float(p.tiltUpDegrees) * toRadians, axis: SIMD3<Float>(1, 0, 0))
    }

    func setOpacity(_ value: Double) {
        let v = Float(min(max(value.isFinite ? value : 1, 0), 1))
        root.isEnabled = v > 0.005
        if v >= 0.995 {
            root.components.remove(OpacityComponent.self)
        } else {
            root.components.set(OpacityComponent(opacity: v))
        }
    }

    // MARK: - Sketch materials
    // "3D sketch" look: flat, unlit light-grey surfaces with dark outlines (like a line drawing
    // of a phone), so lighting never changes how it looks. Tweak the greys here.

    private static func flat(_ white: CGFloat) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(white: white, alpha: 1))
    }

    /// Dark outline colour (also used for the screen edge, island and lenses).
    private static let lineGrey: CGFloat = 0.20

    private let frameClay = PhoneRig.flat(0.80)        // the visible side of the phone
    private let bezelClay = PhoneRig.flat(0.93)        // front face around the screen
    private let screenLineClay = PhoneRig.flat(PhoneRig.lineGrey)  // thin line round the screen
    private let screenSurface = PhoneRig.flat(0.995)   // screen, almost white
    private let backSurface = PhoneRig.flat(0.90)
    private let plateauClay = PhoneRig.flat(0.84)
    private let lensClay = PhoneRig.flat(PhoneRig.lineGrey)
    private let lensRingClay = PhoneRig.flat(0.70)
    private let islandClay = PhoneRig.flat(PhoneRig.lineGrey)
    private let buttonClay = PhoneRig.flat(0.70)

    /// Inverted-hull outline: the side wall, slightly bigger, drawn from the inside only,
    /// so a thin dark line shows around the silhouette from any angle.
    private let outlineMaterial: UnlitMaterial = {
        var m = UnlitMaterial(color: UIColor(white: PhoneRig.lineGrey, alpha: 1))
        m.faceCulling = .front
        return m
    }()

    // MARK: - Geometry Builder

    private func model(_ name: String, _ mesh: MeshResource, _ material: some Material) -> ModelEntity {
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = name
        return entity
    }

    private func buildPhone(into body: Entity) {
        typealias D = PhoneDimensions
        let w = D.width, h = D.height, d = D.depth, half = D.depth / 2

        // 1. Clean Clay Side Frame
        body.addChild(model("ClayFrame",
                            PhoneMeshFactory.sideWall(width: w, height: h, depth: d,
                                                      cornerRadius: D.cornerRadius, bevel: D.bevel,
                                                      cornerSegments: 20, bevelSteps: 6),
                            frameClay))

        // 1b. Outline around the whole body
        let outline = model("Outline",
                            PhoneMeshFactory.sideWall(width: w, height: h, depth: d,
                                                      cornerRadius: D.cornerRadius, bevel: D.bevel,
                                                      cornerSegments: 20, bevelSteps: 6),
                            outlineMaterial)
        outline.scale = SIMD3<Float>(1.03, 1.02, 1.25)
        body.addChild(outline)

        // 2. Front Display
        // Dark bezel border (very thin, just framing)
        body.addChild(model("FrontBezel",
                            PhoneMeshFactory.cap(width: w - 2 * D.bevel, height: h - 2 * D.bevel,
                                                 cornerRadius: D.cornerRadius - D.bevel, z: half, faceFront: true,
                                                 cornerSegments: 20),
                            bezelClay))

        // Thin dark line round the screen
        let lineMargin: Float = 0.0014
        body.addChild(model("ScreenLine",
                            PhoneMeshFactory.cap(width: w - 2 * D.bevel - lineMargin,
                                                 height: h - 2 * D.bevel - lineMargin,
                                                 cornerRadius: D.cornerRadius - D.bevel - lineMargin / 2,
                                                 z: half + 0.00008, faceFront: true,
                                                 cornerSegments: 20),
                            screenLineClay))

        // Screen (plain white)
        let screenMargin: Float = 0.0028
        body.addChild(model("Screen",
                            PhoneMeshFactory.cap(width: w - 2 * D.bevel - screenMargin,
                                                 height: h - 2 * D.bevel - screenMargin,
                                                 cornerRadius: D.cornerRadius - D.bevel - screenMargin / 2,
                                                 z: half + 0.00015, faceFront: true,
                                                 cornerSegments: 20),
                            screenSurface))

        // 3. Dynamic Island — clean pill
        let islandW: Float = 0.0215
        let islandH: Float = 0.0068
        let island = model("DynamicIsland",
                           PhoneMeshFactory.cap(width: islandW, height: islandH, cornerRadius: islandH / 2,
                                                z: half + 0.00028, faceFront: true),
                           islandClay)
        island.position = SIMD3<Float>(0, h / 2 - 0.0105, 0)
        body.addChild(island)

        // 4. Back Panel with Apple Logo texture
        body.addChild(model("BackPanel",
                            PhoneMeshFactory.cap(width: w - 2 * D.bevel, height: h - 2 * D.bevel,
                                                 cornerRadius: D.cornerRadius - D.bevel, z: -half, faceFront: false,
                                                 cornerSegments: 20),
                            backSurface))

        // 5. Minimal Side Buttons (just subtle bumps)
        buildMockupButtons(into: body)

        // 6. Clean Camera Module (no flash, no LiDAR, just lenses + plateau)
        buildMockupCameraModule(into: body)
    }

    // MARK: - Mockup Side Buttons (simple, subtle)

    private func buildMockupButtons(into body: Entity) {
        typealias D = PhoneDimensions
        let edge = D.width / 2 + 0.0001

        func button(_ name: String, x: Float, y: Float, length: Float) {
            let e = model(name, .generateBox(width: 0.0010, height: length, depth: 0.0022, cornerRadius: 0.0004), buttonClay)
            e.position = SIMD3<Float>(x, y, 0)
            body.addChild(e)
        }

        // Left side
        button("ActionButton", x: -edge, y: 0.042, length: 0.0075)
        button("VolumeUp", x: -edge, y: 0.024, length: 0.0125)
        button("VolumeDown", x: -edge, y: 0.005, length: 0.0125)

        // Right side
        button("PowerButton", x: edge, y: 0.020, length: 0.0210)
    }

    // MARK: - Mockup Camera Module (clean, minimal)

    private func buildMockupCameraModule(into body: Entity) {
        typealias D = PhoneDimensions
        let side: Float = 0.0350
        let depth: Float = 0.0014  // slightly shallower than realistic
        let plateau = Entity()
        plateau.name = "CameraPlateau"

        let bumpX = D.width / 2 - side / 2 - 0.0038
        let bumpY = D.height / 2 - side / 2 - 0.0038
        plateau.position = SIMD3<Float>(bumpX, bumpY, -(D.depth / 2 + depth / 2))
        body.addChild(plateau)

        // Plateau — smooth rounded square, same family as frame
        plateau.addChild(model("PlateauWall",
                               PhoneMeshFactory.sideWall(width: side, height: side, depth: depth,
                                                         cornerRadius: 0.0085, bevel: 0.0005,
                                                         cornerSegments: 12, bevelSteps: 3),
                               plateauClay))

        plateau.addChild(model("PlateauFace",
                               PhoneMeshFactory.cap(width: side - 0.0010, height: side - 0.0010, cornerRadius: 0.0080,
                                                    z: -depth / 2, faceFront: false, cornerSegments: 12),
                               plateauClay))

        let faceOutward = simd_quatf(angle: Float.pi / 2, axis: SIMD3<Float>(1, 0, 0))

        // Clean lens builder — just ring + dark circle
        func lens(_ name: String, x: Float, y: Float) {
            let holder = Entity()
            holder.name = name
            holder.position = SIMD3<Float>(x, y, 0)

            // Subtle ring
            let ring = model("LensRing", .generateCylinder(height: 0.0016, radius: 0.0064), lensRingClay)
            ring.orientation = faceOutward
            ring.position = SIMD3<Float>(0, 0, -(depth / 2 + 0.0008))
            holder.addChild(ring)

            // Dark lens disc
            let disc = model("LensDisc", .generateCylinder(height: 0.0018, radius: 0.0050), lensClay)
            disc.orientation = faceOutward
            disc.position = SIMD3<Float>(0, 0, -(depth / 2 + 0.0009))
            holder.addChild(disc)

            plateau.addChild(holder)
        }

        // Triangle arrangement
        lens("MainCamera", x: 0.0082, y: 0.0082)
        lens("UltraWideCamera", x: 0.0082, y: -0.0082)
        lens("TelephotoCamera", x: -0.0082, y: 0.0)
    }
}
