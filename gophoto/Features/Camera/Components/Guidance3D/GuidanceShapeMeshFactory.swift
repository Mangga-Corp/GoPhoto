//
//  GuidanceShapeMeshFactory.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

import RealityKit
import simd

enum GuidanceShapeMeshFactory {

    /// Points of a rounded rectangle, counter-clockwise seen from +Z.
    private static func cornerPoints(halfWidth hw: Float, halfHeight hh: Float,
                                     radius: Float, segments: Int) -> [SIMD2<Float>] {
        let r = max(min(radius, min(hw, hh)), 0.0001)
        let centers: [SIMD2<Float>] = [
            SIMD2(hw - r, hh - r), SIMD2(-(hw - r), hh - r),
            SIMD2(-(hw - r), -(hh - r)), SIMD2(hw - r, -(hh - r)),
        ]
        var points: [SIMD2<Float>] = []
        for (corner, center) in centers.enumerated() {
            let start = Float(corner) * Float.pi / 2
            for s in 0...segments {
                let a = start + Float(s) / Float(segments) * Float.pi / 2
                points.append(center + SIMD2<Float>(cos(a), sin(a)) * r)
            }
        }
        return points
    }

    private static func mesh(positions: [SIMD3<Float>], indices: [UInt32], name: String,
                             fallback: () -> MeshResource) -> MeshResource {
        var descriptor = MeshDescriptor(name: name)
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer([SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 1), count: positions.count))
        descriptor.primitives = .triangles(indices)
        return (try? MeshResource.generate(from: [descriptor])) ?? fallback()
    }

    /// A solid thin outline (ribbon) of a rounded rectangle: the line-art phone.
    static func roundedRectOutline(width: Float, height: Float, cornerRadius: Float,
                                   lineWidth: Float, cornerSegments: Int = 16) -> MeshResource {
        let half = lineWidth / 2
        let inner = cornerPoints(halfWidth: width / 2 - half, halfHeight: height / 2 - half,
                                 radius: cornerRadius - half, segments: cornerSegments)
        let outer = cornerPoints(halfWidth: width / 2 + half, halfHeight: height / 2 + half,
                                 radius: cornerRadius + half, segments: cornerSegments)
        var positions: [SIMD3<Float>] = []
        for i in inner.indices {
            positions.append(SIMD3<Float>(inner[i].x, inner[i].y, 0))
            positions.append(SIMD3<Float>(outer[i].x, outer[i].y, 0))
        }
        let n = inner.count
        var indices: [UInt32] = []
        for j in 0..<n {
            let j2 = (j + 1) % n
            let a = UInt32(2 * j), b = UInt32(2 * j + 1)
            let c = UInt32(2 * j2), d = UInt32(2 * j2 + 1)
            indices += [a, b, c, c, b, d]
        }
        return mesh(positions: positions, indices: indices, name: "LineOutline") {
            MeshResource.generateBox(width: width, height: height, depth: 0.0005)
        }
    }

    /// Dashed rounded-rectangle outline. The dash pattern is stretched slightly so it closes
    /// without a seam.
    static func dashedRoundedRect(width: Float, height: Float, cornerRadius: Float,
                                  dashLength: Float = 0.010, gapLength: Float = 0.0065,
                                  lineWidth: Float = 0.0014, cornerSegments: Int = 16) -> MeshResource {
        var closed = cornerPoints(halfWidth: width / 2, halfHeight: height / 2,
                                  radius: cornerRadius, segments: cornerSegments)
        closed.append(closed[0])

        var runningLength: [Float] = [0]
        for i in 1..<closed.count {
            runningLength.append(runningLength[i - 1] + simd_distance(closed[i - 1], closed[i]))
        }
        let cum = runningLength
        let total = cum[cum.count - 1]

        func sample(_ s: Float) -> (p: SIMD2<Float>, t: SIMD2<Float>) {
            var i = 1
            while i < cum.count - 1 && cum[i] < s { i += 1 }
            let delta = closed[i] - closed[i - 1]
            let length = simd_length(delta)
            let f = min(max((s - cum[i - 1]) / max(length, 1e-6), 0), 1)
            let tangent = length > 1e-6 ? delta / length : SIMD2<Float>(1, 0)
            return (closed[i - 1] + delta * f, tangent)
        }

        let dashCount = max(1, Int((total / (dashLength + gapLength)).rounded()))
        let period = total / Float(dashCount)
        let dash = period * dashLength / (dashLength + gapLength)
        let steps = max(2, Int((dash / 0.002).rounded(.up)))

        var positions: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for k in 0..<dashCount {
            let s0 = Float(k) * period
            let base = UInt32(positions.count)
            for j in 0...steps {
                let s = s0 + dash * Float(j) / Float(steps)
                let (p, t) = sample(s)
                let outward = SIMD2<Float>(t.y, -t.x)               // outline is counter-clockwise
                let inner = p - outward * (lineWidth / 2)
                let outer = p + outward * (lineWidth / 2)
                positions.append(SIMD3<Float>(inner.x, inner.y, 0))
                positions.append(SIMD3<Float>(outer.x, outer.y, 0))
            }
            for j in 0..<steps {
                let i0 = base + UInt32(2 * j)
                indices += [i0, i0 + 1, i0 + 2, i0 + 2, i0 + 1, i0 + 3]
            }
        }
        return mesh(positions: positions, indices: indices, name: "GhostOutline") {
            MeshResource.generateBox(width: width, height: height, depth: 0.0005)
        }
    }

    /// A chevron pointing UP ("^"), centred on the origin. Rotate it 180° about Z for "v".
    static func chevron(halfWidth w: Float = 0.0125, drop h: Float = 0.0075,
                        thickness c: Float = 0.0034) -> MeshResource {
        let shift = (h + c) / 2
        let points: [(Float, Float)] = [(-w, -h), (0, 0), (0, -c), (-w, -h - c), (w, -h - c), (w, -h)]
        let positions = points.map { SIMD3<Float>($0.0, $0.1 + shift, 0) }
        let indices: [UInt32] = [0, 3, 2, 0, 2, 1, 1, 2, 4, 1, 4, 5]
        return mesh(positions: positions, indices: indices, name: "Chevron") {
            MeshResource.generateBox(width: 2 * w, height: h + c, depth: 0.0005)
        }
    }
}
