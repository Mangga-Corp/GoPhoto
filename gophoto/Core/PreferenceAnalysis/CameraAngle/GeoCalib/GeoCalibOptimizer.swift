// Derived from GeoCalib (https://github.com/cvg/GeoCalib), geocalib/lm_optimizer.py, perspective_fields.py, gravity.py, camera.py.
// Copyright 2024 ETH Zurich. Licensed under the Apache License, Version 2.0
// (see ThirdPartyNotices/GeoCalib/LICENSE). MODIFIED: ported from Python/PyTorch to Swift,
// pinhole camera and single image only, by the GoPhoto team, October 2026.

import Foundation

// GeoCalib Levenberg–Marquardt optimizer — pinhole camera, one image, no priors.
//
// Swift port of geocalib/lm_optimizer.py (cvg/GeoCalib, Apache-2.0). It turns the network's
// perspective fields (up-vectors + latitudes + confidences) into roll, pitch and focal length.
// Line-by-line twin of gc_optimizer_np.py, which matches the official PyTorch optimizer
// to 4 decimals on the test photos (verify_np.py). GeoCalibOptimizerTests checks this file
// against the same numbers.

/// Network outputs at network resolution (row-major, `height * width` values each).
nonisolated struct GeoCalibFields: Sendable {
    let width: Int
    let height: Int
    let upX: [Float]
    let upY: [Float]
    let upConfidence: [Float]
    /// sin(latitude) — the optimizer compares sines, so store them directly.
    let sinLatitude: [Float]
    let latitudeConfidence: [Float]

    init(width: Int, height: Int, upX: [Float], upY: [Float], upConfidence: [Float],
         latitude: [Float], latitudeConfidence: [Float]) {
        precondition(upX.count == width * height && upY.count == width * height
                     && upConfidence.count == width * height && latitude.count == width * height
                     && latitudeConfidence.count == width * height, "field sizes do not match")
        self.width = width
        self.height = height
        self.upX = upX
        self.upY = upY
        self.upConfidence = upConfidence
        self.sinLatitude = latitude.map { Float(sin(Double($0))) }
        self.latitudeConfidence = latitudeConfidence
    }
}

/// Camera estimate in ORIGINAL image pixels. Angles in degrees.
nonisolated struct GeoCalibResult: Sendable, Codable, Equatable {
    /// Positive/negative as in GeoCalib. Check the sign convention with a known tilted photo.
    var roll: Double
    /// Latitude of the image centre: negative = camera looking down, positive = looking up.
    var pitch: Double
    var focalPx: Double
    var focalXPx: Double
    var vfov: Double
    /// One standard deviation, from the optimizer's Hessian.
    var rollUncertainty: Double
    var pitchUncertainty: Double
    var focalUncertaintyPx: Double
    var vfovUncertainty: Double
    var steps: Int
    /// Up direction in camera coordinates (x right, y down, z forward).
    var up: [Double]
    /// Principal point and image size in original pixels.
    var cx: Double
    var cy: Double
    var imageWidth: Double
    var imageHeight: Double

    /// Angle of an image point above (+) / below (−) the camera's horizontal plane, in degrees.
    /// Use it for "the eyes are 25° below the camera".
    func elevation(x: Double, y: Double) -> Double {
        let u = (x - cx) / focalXPx, v = (y - cy) / focalPx
        let n = (u * u + v * v + 1).squareRoot()
        let d = (u * up[0] + v * up[1] + up[2]) / n
        return asin(min(max(d, -1), 1)) * 180 / .pi
    }
}

nonisolated enum GeoCalibOptimizer {
    static let upLossScale = 1e-2
    static let latLossScale = 1e-2
    static let numSteps = 30
    static let lambda0 = 0.1
    static let atol = 1e-8
    static let rtol = 1e-8

    /// - Parameters:
    ///   - scaleX, scaleY: resized size / original size (before the crop).
    ///   - cropPadX, cropPadY: cropped size − resized size (≤ 0).
    static func calibrate(_ f: GeoCalibFields, scaleX: Double, scaleY: Double,
                          cropPadX: Double, cropPadY: Double) -> GeoCalibResult {
        let W = Double(f.width), H = Double(f.height)
        let cx = W / 2, cy = H / 2
        let f0 = 0.7 * max(H, W)
        var fy = f0
        var fx = f0 * scaleX / scaleY
        var g = gravityFromRollPitch(0, 0)
        let minF = H / 2 / tan(150.0 * .pi / 180 / 2)
        let maxF = H / 2 / tan(5.0 * .pi / 180 / 2)

        var lambda = lambda0
        var prev = 0.0
        var steps = numSteps
        for i in 0..<numSteps {
            let e = evaluate(f, g: g, fx: fx, fy: fy, cx: cx, cy: cy, mode: .optimize)
            if i == 0 { prev = e.cost }
            var damped = e.hessian
            for k in 0..<3 { damped[k * 3 + k] += max(e.hessian[k * 3 + k] * lambda, 1e-6) }
            let delta = choleskySolve3(damped, e.gradient) ?? [0, 0, 0]

            g = manifoldPlus(g, delta[0], delta[1])
            let newFy = min(max(exp(log(fy) + delta[2]), minF), maxF)
            fx = newFy * fx / fy   // keep the fx/fy ratio (fx is updated through fy, as in GeoCalib)
            fy = newFy

            let newCost = evaluate(f, g: g, fx: fx, fy: fy, cx: cx, cy: cy, mode: .cost).cost
            lambda = min(max(lambda * (newCost > prev ? 10 : 0.1), 1e-6), 1e2)
            if abs(newCost - prev) <= atol + rtol * abs(prev) {
                steps = i + 1
                break
            }
            prev = newCost
        }

        // Uncertainty w.r.t. (roll, pitch, f), no damping.
        let hr = evaluate(f, g: g, fx: fx, fy: fy, cx: cx, cy: cy, mode: .rollPitchFocal).hessian
        let cov = inverse3(hr) ?? [Double](repeating: .nan, count: 9)
        let (roll, pitch) = rollPitch(g)
        let focalVar = cov[8]
        let jFocal2Fov = -4 * H / (4 * fy * fy + H * H)

        let fyOrig = fy / scaleY
        let fxOrig = fx / scaleX
        let wOrig = (W - cropPadX) / scaleX
        let hOrig = (H - cropPadY) / scaleY
        let deg = 180.0 / .pi
        return GeoCalibResult(
            roll: roll * deg, pitch: pitch * deg,
            focalPx: fyOrig, focalXPx: fxOrig,
            vfov: 2 * atan(hOrig / (2 * fyOrig)) * deg,
            rollUncertainty: cov[0].squareRoot() * deg,
            pitchUncertainty: cov[4].squareRoot() * deg,
            focalUncertaintyPx: focalVar.squareRoot() / 2 / scaleY,
            vfovUncertainty: (jFocal2Fov * jFocal2Fov * focalVar / 2).squareRoot() * deg,
            steps: steps, up: [g.0, g.1, g.2],
            cx: wOrig / 2, cy: hOrig / 2, imageWidth: wOrig, imageHeight: hOrig)
    }

    // MARK: - Cost, gradient, Hessian

    enum Mode { case cost, optimize, rollPitchFocal }

    struct Evaluation {
        var cost: Double
        var gradient: [Double]   // 3
        var hessian: [Double]    // 3x3 row-major
    }

    typealias Vec3 = (Double, Double, Double)

    static func evaluate(_ f: GeoCalibFields, g: Vec3, fx: Double, fy: Double, cx: Double, cy: Double,
                         mode: Mode) -> Evaluation {
        let (a, b, c) = g
        // d(up vector) / d(parameters 0, 1): manifold tangent while optimizing, roll/pitch for the covariance.
        let jg: [Double] = mode == .rollPitchFocal ? jRollPitch(g) : jPlus(g)   // 3x2 row-major
        let j00 = jg[0], j01 = jg[1], j10 = jg[2], j11 = jg[3], j20 = jg[4], j21 = jg[5]
        let a2u = upLossScale * upLossScale
        let a2l = latLossScale * latLossScale

        var upCost = 0.0, latCost = 0.0
        var g0 = 0.0, g1 = 0.0, g2 = 0.0
        var h00 = 0.0, h01 = 0.0, h02 = 0.0, h11 = 0.0, h12 = 0.0, h22 = 0.0

        let width = f.width
        f.upX.withUnsafeBufferPointer { upX in
        f.upY.withUnsafeBufferPointer { upY in
        f.upConfidence.withUnsafeBufferPointer { upC in
        f.sinLatitude.withUnsafeBufferPointer { sLat in
        f.latitudeConfidence.withUnsafeBufferPointer { latC in
            for yi in 0..<f.height {
                let py = Double(yi)
                let v = (py - cy) / fy
                for xi in 0..<width {
                    let i = yi * width + xi
                    let px = Double(xi)
                    let u = (px - cx) / fx

                    // Up-vector model and residual.
                    let p0 = a - c * u, p1 = b - c * v
                    var pn = (p0 * p0 + p1 * p1).squareRoot()
                    if pn == 0 { pn = 1e-6 }
                    let r0 = Double(upX[i]) - p0 / pn
                    let r1 = Double(upY[i]) - p1 / pn

                    // Latitude model (sine) and residual.
                    let rn = (u * u + v * v + 1).squareRoot()
                    let n0 = u / rn, n1 = v / rn, n2 = 1 / rn
                    let d = min(max(n0 * a + n1 * b + n2 * c, -1 + 1e-6), 1 - 1e-6)
                    let rl = Double(sLat[i]) - d

                    let (uc, uw) = huber(r0 * r0 + r1 * r1, a2u)
                    let (lc, lw) = huber(rl * rl, a2l)
                    let upConf = Double(upC[i]), latConf = Double(latC[i])
                    upCost += uc * upConf
                    latCost += lc * latConf
                    if mode == .cost { continue }

                    let wu = uw * upConf, wl = lw * latConf

                    // J_norm2proj = I/|p| − p pᵀ/|p|³
                    let inv = 1 / pn, inv3 = inv * inv * inv
                    let A00 = inv - p0 * p0 * inv3, A01 = -p0 * p1 * inv3, A11 = inv - p1 * p1 * inv3
                    // d(up)/d(g) rows = A · [[1,0,−u],[0,1,−v]], then · jg
                    let ua0 = A00, ua1 = A01, ua2 = -(A00 * u + A01 * v)
                    let ub0 = A01, ub1 = A11, ub2 = -(A01 * u + A11 * v)
                    let ju00 = ua0 * j00 + ua1 * j10 + ua2 * j20
                    let ju01 = ua0 * j01 + ua1 * j11 + ua2 * j21
                    let ju10 = ub0 * j00 + ub1 * j10 + ub2 * j20
                    let ju11 = ub0 * j01 + ub1 * j11 + ub2 * j21
                    let jl0 = n0 * j00 + n1 * j10 + n2 * j20
                    let jl1 = n0 * j01 + n1 * j11 + n2 * j21

                    // Focal: d(u, v)/d(log f) = (−u, −v) while optimizing, d(u, v)/d f for the covariance.
                    let du: Double, dv: Double
                    if mode == .optimize { du = -u; dv = -v } else { du = -(px - cx) / (fx * fx); dv = -(py - cy) / (fy * fy) }
                    let q0 = -c * du, q1 = -c * dv
                    let ju02 = A00 * q0 + A01 * q1
                    let ju12 = A01 * q0 + A11 * q1
                    let invR = 1 / rn, invR3 = invR * invR * invR
                    let w0 = (invR - u * u * invR3) * du + (-u * v * invR3) * dv
                    let w1 = (-v * u * invR3) * du + (invR - v * v * invR3) * dv
                    let w2 = (-u * invR3) * du + (-v * invR3) * dv
                    let jl2 = w0 * a + w1 * b + w2 * c

                    // Gradient Σ w Jᵀ r and Gauss–Newton Hessian Σ w Jᵀ J.
                    g0 += wu * (r0 * ju00 + r1 * ju10) + wl * rl * jl0
                    g1 += wu * (r0 * ju01 + r1 * ju11) + wl * rl * jl1
                    g2 += wu * (r0 * ju02 + r1 * ju12) + wl * rl * jl2
                    h00 += wu * (ju00 * ju00 + ju10 * ju10) + wl * jl0 * jl0
                    h01 += wu * (ju00 * ju01 + ju10 * ju11) + wl * jl0 * jl1
                    h02 += wu * (ju00 * ju02 + ju10 * ju12) + wl * jl0 * jl2
                    h11 += wu * (ju01 * ju01 + ju11 * ju11) + wl * jl1 * jl1
                    h12 += wu * (ju01 * ju02 + ju11 * ju12) + wl * jl1 * jl2
                    h22 += wu * (ju02 * ju02 + ju12 * ju12) + wl * jl2 * jl2
                }
            }
        }}}}}

        let n = Double(f.width * f.height)
        return Evaluation(cost: upCost / n + latCost / n,
                          gradient: [g0, g1, g2],
                          hessian: [h00, h01, h02, h01, h11, h12, h02, h12, h22])
    }

    /// Scaled Huber loss: (loss, weight) — same as scaled_loss(x, huber_loss, a) in GeoCalib.
    @inline(__always)
    static func huber(_ cost: Double, _ a2: Double) -> (Double, Double) {
        let x = cost / a2
        if x <= 1 { return (x * a2, 1) }
        let sx = (x + 1e-8).squareRoot()
        return ((2 * sx - 1) * a2, max(Double(Float.ulpOfOne), 1 / sx))
    }

    // MARK: - Gravity / manifold

    static func gravityFromRollPitch(_ roll: Double, _ pitch: Double) -> Vec3 {
        let v = (-sin(roll) * cos(pitch), -cos(roll) * cos(pitch), sin(pitch))
        return normalized(v)
    }

    static func rollPitch(_ g: Vec3) -> (Double, Double) {
        let (x, y, z) = g
        let pitch = asin(min(max(z, -1), 1))
        var roll = asin(min(max(-x / (max(0, 1 - z * z).squareRoot() + 1e-4), -1), 1))
        if y >= 0 { roll = -roll - .pi * sign(x) }
        return (roll, pitch)
    }

    static func sign(_ x: Double) -> Double { x > 0 ? 1 : (x < 0 ? -1 : 0) }

    /// d g / d(roll, pitch), 3x2 row-major.
    static func jRollPitch(_ g: Vec3) -> [Double] {
        let (roll, pitch) = rollPitch(g)
        let cp = cos(pitch), sp = sin(pitch), cr = cos(roll), sr = sin(roll)
        return [-cr * cp, sr * sp,
                sr * cp, cr * sp,
                0, cp]
    }

    static func householder(_ x: Vec3) -> (Vec3, Double) {
        var sigma = x.0 * x.0 + x.1 * x.1
        let xpiv = x.2
        let norm = (x.0 * x.0 + x.1 * x.1 + x.2 * x.2).squareRoot()
        if sigma < 1e-7 { sigma += 1e-7 }
        let vpiv = xpiv < 0 ? xpiv - norm : -sigma / (xpiv + norm)
        let beta = 2 * vpiv * vpiv / (sigma + vpiv * vpiv)
        return ((x.0 / vpiv, x.1 / vpiv, 1), beta)
    }

    /// Spherical-manifold plus-Jacobian, 3x2 row-major.
    static func jPlus(_ x: Vec3) -> [Double] {
        let (v, beta) = householder(x)
        let vv = [v.0, v.1, v.2]
        var out = [Double](repeating: 0, count: 6)
        for r in 0..<3 {
            for k in 0..<2 {
                out[r * 2 + k] = (r == k ? 1 : 0) - beta * vv[r] * vv[k]
            }
        }
        return out
    }

    static func manifoldPlus(_ x: Vec3, _ d0: Double, _ d1: Double) -> Vec3 {
        let eps = 1e-7
        let nx = (x.0 * x.0 + x.1 * x.1 + x.2 * x.2).squareRoot()
        let nd = (d0 * d0 + d1 * d1).squareRoot()
        let sinc = nd < eps ? 1 : sin(nd) / nd
        let e = (sinc * d0, sinc * d1, cos(nd))
        let (v, beta) = householder(x)
        let dot = v.0 * e.0 + v.1 * e.1 + v.2 * e.2
        let y = (nx * (e.0 - v.0 * beta * dot), nx * (e.1 - v.1 * beta * dot), nx * (e.2 - v.2 * beta * dot))
        return normalized(y)
    }

    static func normalized(_ v: Vec3) -> Vec3 {
        let n = (v.0 * v.0 + v.1 * v.1 + v.2 * v.2).squareRoot()
        return (v.0 / n, v.1 / n, v.2 / n)
    }

    // MARK: - 3x3 linear algebra

    /// Solves A x = b with Cholesky; nil when A is not positive definite (GeoCalib then takes no step).
    static func choleskySolve3(_ A: [Double], _ b: [Double]) -> [Double]? {
        var L = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0...i {
                var s = A[i * 3 + j]
                for k in 0..<j { s -= L[i * 3 + k] * L[j * 3 + k] }
                if i == j {
                    guard s > 0 else { return nil }
                    L[i * 3 + i] = s.squareRoot()
                } else {
                    L[i * 3 + j] = s / L[j * 3 + j]
                }
            }
        }
        var y = [0.0, 0.0, 0.0]
        for i in 0..<3 {
            var s = b[i]
            for k in 0..<i { s -= L[i * 3 + k] * y[k] }
            y[i] = s / L[i * 3 + i]
        }
        var x = [0.0, 0.0, 0.0]
        for i in stride(from: 2, through: 0, by: -1) {
            var s = y[i]
            for k in (i + 1)..<3 { s -= L[k * 3 + i] * x[k] }
            x[i] = s / L[i * 3 + i]
        }
        return x
    }

    static func inverse3(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
        let det = a * A + b * B + c * C
        guard det != 0, det.isFinite else { return nil }
        let D = -(b * i - c * h), E = a * i - c * g, F = -(a * h - b * g)
        let G = b * f - c * e, H = -(a * f - c * d), I = a * e - b * d
        return [A / det, D / det, G / det,
                B / det, E / det, H / det,
                C / det, F / det, I / det]
    }
}
