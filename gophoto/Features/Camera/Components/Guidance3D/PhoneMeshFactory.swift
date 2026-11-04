//
//  PhoneMeshFactory.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import RealityKit
import simd

enum PhoneMeshFactory {

    private struct Ring {
        let inset: Float   // how far the outline is pulled inward
        let z: Float
        let nxy: Float     // share of the normal that points outward in the XY plane
        let nz: Float
    }

    /// Rounded rectangle outline, counter-clockwise seen from +Z, with outward 2D normals.
    private static func outline(halfWidth hw: Float, halfHeight hh: Float, radius: Float, segments: Int)
        -> (points: [SIMD2<Float>], normals: [SIMD2<Float>]) {
        let r = max(min(radius, min(hw, hh)), 0.0001)
        let centers: [SIMD2<Float>] = [
            SIMD2(hw - r, hh - r), SIMD2(-(hw - r), hh - r),
            SIMD2(-(hw - r), -(hh - r)), SIMD2(hw - r, -(hh - r)),
        ]
        var points: [SIMD2<Float>] = []
        var normals: [SIMD2<Float>] = []
        for (corner, center) in centers.enumerated() {
            let start = Float(corner) * Float.pi / 2
            for s in 0...segments {
                let angle = start + Float(s) / Float(segments) * Float.pi / 2
                let n = SIMD2<Float>(cos(angle), sin(angle))
                points.append(center + n * r)
                normals.append(n)
            }
        }
        return (points, normals)
    }

    /// The side of the slab: bevel at the front, straight wall, bevel at the back.
    /// Centered on the origin, thickness along Z.
    static func sideWall(width: Float, height: Float, depth: Float, cornerRadius: Float,
                         bevel: Float, cornerSegments: Int = 14, bevelSteps: Int = 4) -> MeshResource {
        let half = depth / 2
        let b = min(bevel, half * 0.9)

        var rings: [Ring] = []
        for k in 0...bevelSteps {                                   // front half, face -> wall
            let t = Float(k) / Float(bevelSteps) * Float.pi / 2
            rings.append(Ring(inset: b * (1 - sin(t)), z: (half - b) + b * cos(t), nxy: sin(t), nz: cos(t)))
        }
        for k in stride(from: bevelSteps, through: 0, by: -1) {     // back half, wall -> face
            let t = Float(k) / Float(bevelSteps) * Float.pi / 2
            rings.append(Ring(inset: b * (1 - sin(t)), z: -((half - b) + b * cos(t)), nxy: sin(t), nz: -cos(t)))
        }

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for ring in rings {
            let o = outline(halfWidth: width / 2 - ring.inset, halfHeight: height / 2 - ring.inset,
                            radius: cornerRadius - ring.inset, segments: cornerSegments)
            for i in o.points.indices {
                positions.append(SIMD3<Float>(o.points[i].x, o.points[i].y, ring.z))
                normals.append(simd_normalize(SIMD3<Float>(o.normals[i].x * ring.nxy,
                                                           o.normals[i].y * ring.nxy,
                                                           ring.nz)))
            }
        }

        let n = 4 * (cornerSegments + 1)
        var indices: [UInt32] = []
        for r in 0..<(rings.count - 1) {
            for j in 0..<n {
                let j2 = (j + 1) % n
                let a = UInt32(r * n + j), a2 = UInt32(r * n + j2)
                let c = UInt32((r + 1) * n + j), c2 = UInt32((r + 1) * n + j2)
                indices += [a, c, a2, a2, c, c2]                     // counter-clockwise from outside
            }
        }

        var descriptor = MeshDescriptor(name: "PhoneSideWall")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generateBox(width: width, height: height, depth: depth)
    }

    /// A flat rounded-rectangle plate at height `z`, facing +Z (front) or -Z (back).
    static func cap(width: Float, height: Float, cornerRadius: Float, z: Float,
                    faceFront: Bool, cornerSegments: Int = 14) -> MeshResource {
        let o = outline(halfWidth: width / 2, halfHeight: height / 2,
                        radius: cornerRadius, segments: cornerSegments)
        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, z)]
        positions += o.points.map { SIMD3<Float>($0.x, $0.y, z) }
        let nz: Float = faceFront ? 1 : -1
        let normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, nz), count: positions.count)

        var uvs: [SIMD2<Float>] = [SIMD2<Float>(0.5, 0.5)]
        for p in o.points {
            let u = faceFront ? (p.x + width / 2) / width : (width / 2 - p.x) / width
            let v = 1.0 - (p.y + height / 2) / height
            uvs.append(SIMD2<Float>(u, v))
        }

        let n = o.points.count
        var indices: [UInt32] = []
        for j in 0..<n {
            let p0 = UInt32(1 + j), p1 = UInt32(1 + (j + 1) % n)
            if faceFront { indices += [0, p0, p1] } else { indices += [0, p1, p0] }
        }

        var descriptor = MeshDescriptor(name: "PhoneCap")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor]))
            ?? MeshResource.generateBox(width: width, height: height, depth: 0.001)
    }
}
