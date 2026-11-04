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
    // Standard flagship iPhone Pro proportions (metres)
    static let width: Float = 0.0715        // 71.5 mm
    static let height: Float = 0.1476       // 147.6 mm
    static let depth: Float = 0.0082        // 8.2 mm
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

    // MARK: - Clean Mockup Materials

    /// Smooth, matte clay body — like a premium device mockup render.
    /// Very low metallic, medium roughness = soft diffuse clay feel.
    private static func mockupClay(
        _ color: UIColor,
        roughness: Float = 0.55,
        metallic: Float = 0.0
    ) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.metallic = .init(floatLiteral: metallic)
        m.roughness = .init(floatLiteral: roughness)
        return m
    }

    private static func mockupPBR(
        _ color: UIColor,
        metallic: Float = 0.0,
        roughness: Float = 0.5,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.1,
        emissiveColor: UIColor? = nil,
        emissiveIntensity: Float = 0,
        texture: TextureResource? = nil
    ) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if let texture {
            m.baseColor = .init(tint: color, texture: .init(texture))
        } else {
            m.baseColor = .init(tint: color)
        }
        m.metallic = .init(floatLiteral: metallic)
        m.roughness = .init(floatLiteral: roughness)
        if clearcoat > 0 {
            m.clearcoat = .init(floatLiteral: clearcoat)
            m.clearcoatRoughness = .init(floatLiteral: clearcoatRoughness)
        }
        if let emissiveColor {
            if let texture {
                m.emissiveColor = .init(color: emissiveColor, texture: .init(texture))
            } else {
                m.emissiveColor = .init(color: emissiveColor)
            }
            m.emissiveIntensity = emissiveIntensity
        }
        return m
    }

    // ─── Mockup palette ───────────────────────────────────────────────

    /// Soft silver-white clay frame — the signature mockup look
    private let frameClay = PhoneRig.mockupClay(
        UIColor(red: 0.82, green: 0.83, blue: 0.86, alpha: 1),
        roughness: 0.52, metallic: 0.05
    )

    /// Front bezel — very dark matte, just barely visible edge
    private let bezelClay = PhoneRig.mockupClay(
        UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1),
        roughness: 0.35
    )

    /// Screen surface — dark with subtle texture, gentle glow
    private lazy var screenSurface: PhysicallyBasedMaterial = {
        let texture = IPhoneTextureGenerator.getScreenTexture()
        return PhoneRig.mockupPBR(
            UIColor.white,
            metallic: 0.0,
            roughness: 0.15,
            clearcoat: 0.3,
            clearcoatRoughness: 0.08,
            emissiveColor: UIColor(white: 1.0, alpha: 1),
            emissiveIntensity: 0.20,
            texture: texture
        )
    }()

    /// Back panel — soft satin clay, just slightly warmer than frame
    private lazy var backSurface: PhysicallyBasedMaterial = {
        let texture = IPhoneTextureGenerator.getBackTexture()
        return PhoneRig.mockupPBR(
            UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1),
            metallic: 0.02,
            roughness: 0.55,
            texture: texture
        )
    }()

    /// Camera plateau — slightly darker than back, still clay
    private let plateauClay = PhoneRig.mockupClay(
        UIColor(red: 0.74, green: 0.75, blue: 0.78, alpha: 1),
        roughness: 0.45, metallic: 0.03
    )

    /// Camera lens — clean dark circle, not shiny
    private let lensClay = PhoneRig.mockupClay(
        UIColor(red: 0.12, green: 0.13, blue: 0.15, alpha: 1),
        roughness: 0.30
    )

    /// Lens ring — subtle lighter ring around the lens
    private let lensRingClay = PhoneRig.mockupClay(
        UIColor(red: 0.68, green: 0.69, blue: 0.72, alpha: 1),
        roughness: 0.40, metallic: 0.08
    )

    /// Dynamic Island pill — dark matte
    private let islandClay = PhoneRig.mockupClay(
        UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1),
        roughness: 0.25
    )

    /// Side button clay — same as frame but slightly darker
    private let buttonClay = PhoneRig.mockupClay(
        UIColor(red: 0.72, green: 0.73, blue: 0.76, alpha: 1),
        roughness: 0.48, metallic: 0.06
    )

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

        // 2. Front Display
        // Dark bezel border (very thin, just framing)
        body.addChild(model("FrontBezel",
                            PhoneMeshFactory.cap(width: w - 2 * D.bevel, height: h - 2 * D.bevel,
                                                 cornerRadius: D.cornerRadius - D.bevel, z: half, faceFront: true,
                                                 cornerSegments: 20),
                            bezelClay))

        // Screen with minimal UI texture
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
