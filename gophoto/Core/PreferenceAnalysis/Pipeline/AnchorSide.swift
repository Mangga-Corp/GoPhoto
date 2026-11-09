//
//  AnchorSide.swift
//  gophoto
//
//  Camera height against ONE body anchor per shot size, two classes only (above / below), version 16.
//  Ported from the debugphoto QA app (anchor-side-v3 + robust aggregate + shooting styles).
//
import Foundation
import CoreGraphics

/// Per shot size the photos vote "camera above" vs "camera below" one body anchor:
///   Full body → knee · Three-quarter → chest (shoulder line, else the neck) · Half body → eyes.
///   One-quarter has no anchor (the eye-line vote applies).
/// Every measured photo votes on its nominal side (uncertain ones too); a tie decides nothing.
/// Only the winning side's photos make the target. With `styleMinPhotos` or more, the winning
/// side is split into shooting styles (1-D split by the anchor angle) and only the biggest is used,
/// so the target is a way people actually shoot, not a median that falls between two styles.
nonisolated enum AnchorSide {

    nonisolated enum Anchor: String, Sendable { case knee, chest, eye }
    nonisolated enum Side: String, Sendable { case above, below }

    /// Fewer winning photos than this: use them all (no style split).
    static let styleMinPhotos = 6
    /// A style needs at least this many photos.
    static let styleMinGroup = 3
    /// Each extra style must explain at least this much more of the angle spread.
    static let styleMinGain = 0.15
    static let styleMaxCount = 3

    static func anchor(for shot: PresetAnalysis.ShotSize?) -> Anchor? {
        switch shot {
        case .full?: .knee
        case .threeQuarter?: .chest
        case .half?: .eye
        default: nil
        }
    }

    /// The vote and the photos the target is made from.
    nonisolated struct Pick: Sendable, Equatable {
        let anchor: Anchor
        let above: Int
        let below: Int
        let side: Side
        /// Indices into the `results` passed to `pick`: the chosen style (or the whole winning side).
        let indices: [Int]
        /// Shooting styles found on the winning side (1 = not split).
        let styleCount: Int
    }

    /// Camera vs the anchor, degrees (+ = camera above the anchor), and one standard deviation.
    nonisolated struct Reading: Sendable, Equatable {
        let elevation: Double
        let sigma: Double?
    }

    static func pick(_ results: [PhotoResult], anchor: Anchor) -> Pick? {
        var readings: [(index: Int, reading: Reading)] = []
        for i in results.indices {
            if let r = reading(results[i], anchor: anchor) { readings.append((index: i, reading: r)) }
        }
        let above = readings.filter { $0.reading.elevation > 0 }
        let below = readings.filter { $0.reading.elevation <= 0 }
        guard above.count != below.count else { return nil }
        let side: Side = above.count > below.count ? .above : .below
        let winners = side == .above ? above : below
        var chosen = winners.map { $0.index }
        var styleCount = 1
        if winners.count >= styleMinPhotos {
            let groups = styles(winners.map { $0.reading })
            styleCount = groups.count
            if groups.count > 1 {
                let overall = median(winners.map { $0.reading.elevation })
                func distance(_ g: [Int]) -> Double { abs(median(g.map { winners[$0].reading.elevation }) - overall) }
                // Biggest style; on a tie the one nearest the side's median.
                if let biggest = groups.max(by: { a, b in a.count != b.count ? a.count < b.count : distance(a) > distance(b) }) {
                    chosen = biggest.map { winners[$0].index }
                }
            }
        }
        return Pick(anchor: anchor, above: above.count, below: below.count, side: side,
                    indices: chosen.sorted(), styleCount: styleCount)
    }

    /// One photo's reading against `anchor`, or nil when the anchor or GeoCalib was not read.
    static func reading(_ result: PhotoResult, anchor: Anchor) -> Reading? {
        guard let detail = result.angleComparison?.details[.geoCalibLight] else { return nil }
        if anchor == .eye {
            // The eye line is GoPhoto's own camera-vs-eyes angle.
            guard let e = detail.cameraElevation, e.isFinite else { return nil }
            return Reading(elevation: e, sigma: detail.cameraElevationUncertainty)
        }
        guard let calibration = detail.calibration, let box = result.subjectPositioning.subjectBox,
              let poses = result.evidence?.pose.value,
              let pose = SubjectAssociation.pose(for: box, among: poses) else { return nil }
        // Knee: mean of the reliable knees. Chest: the shoulder line, else the neck joint.
        let groups: [[BodyJoint]] = anchor == .knee
            ? [[.leftKnee, .rightKnee]]
            : [[.leftShoulder, .rightShoulder], [.neck]]
        for joints in groups {
            let points = joints.compactMap { pose.reliable($0)?.point }
            guard !points.isEmpty else { continue }
            let n = CGFloat(points.count)
            let point = CGPoint(x: points.reduce(0) { $0 + $1.x } / n, y: points.reduce(0) { $0 + $1.y } / n)
            return reading(calibration, point: point, focalLength35mm: detail.focalLength35mm)
        }
        return nil
    }

    /// Same geometry as the camera-vs-eyes angle: EXIF focal length when known, else GeoCalib's;
    /// sigma from pitch, roll and (without EXIF) focal uncertainty by finite differences.
    static func reading(_ r: GeoCalibResult, point: CGPoint, focalLength35mm: Double?) -> Reading? {
        guard r.up.count == 3, r.up.allSatisfy(\.isFinite), r.imageWidth > 0, r.imageHeight > 0,
              r.focalPx > 0, r.focalXPx > 0, point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else { return nil }
        let w = r.imageWidth, h = r.imageHeight
        var lens = r
        var fromExif = false
        if let mm = focalLength35mm, mm > 0 {
            let focal = mm / GeoCalibAngleInterpreter.fullFrameDiagonalMM * (w * w + h * h).squareRoot()
            lens.focalPx = focal
            lens.focalXPx = focal
            fromExif = true
        }
        let x = Double(point.x) * w, y = Double(point.y) * h
        let elevation = -lens.elevation(x: x, y: y)
        guard elevation.isFinite else { return nil }
        guard r.pitchUncertainty.isFinite, r.pitchUncertainty >= 0,
              r.rollUncertainty.isFinite, r.rollUncertainty >= 0 else { return Reading(elevation: elevation, sigma: nil) }
        var variance = 0.0
        for component in 0..<3 {
            if component == 2 && (fromExif || !r.focalUncertaintyPx.isFinite || r.focalUncertaintyPx >= lens.focalPx) { continue }
            var values: [Double] = []
            for sign in [-1.0, 1.0] {
                var p = lens
                if component == 0 { p.pitch += sign * r.pitchUncertainty }
                if component == 1 { p.roll += sign * r.rollUncertainty }
                if component == 2 {
                    p.focalPx += sign * r.focalUncertaintyPx
                    p.focalXPx *= p.focalPx / lens.focalPx
                }
                if component < 2 {
                    let g = GeoCalibOptimizer.gravityFromRollPitch(p.roll * .pi / 180, p.pitch * .pi / 180)
                    p.up = [g.0, g.1, g.2]
                }
                values.append(-p.elevation(x: x, y: y))
            }
            let delta = (values[1] - values[0]) / 2
            variance += delta * delta
        }
        let sigma = variance.squareRoot()
        return Reading(elevation: elevation, sigma: sigma.isFinite ? sigma : nil)
    }

    /// Optimal 1-D split (least within-style squared error) into 1…`styleMaxCount` styles, as index
    /// groups into `readings`, lowest angle first. A split is kept only when it explains
    /// `styleMinGain` more of the spread and neighbouring style medians are at least the median
    /// sigma apart (so a style is not measurement noise).
    static func styles(_ readings: [Reading]) -> [[Int]] {
        let order = readings.indices.sorted { readings[$0].elevation < readings[$1].elevation }
        let v = order.map { readings[$0].elevation }
        let n = v.count
        guard n >= styleMinGroup * 2 else { return [order] }
        func sse(_ a: Int, _ b: Int) -> Double {
            let part = v[a..<b], m = part.reduce(0, +) / Double(b - a)
            return part.reduce(0) { $0 + ($1 - m) * ($1 - m) }
        }
        let total = sse(0, n)
        guard total > 0 else { return [order] }
        let sigmas = readings.compactMap(\.sigma).filter(\.isFinite)
        let minGap = sigmas.isEmpty ? 0 : median(sigmas)
        var bounds = [0, n], fit = 0.0
        for k in 2...styleMaxCount {
            var best: (cost: Double, bounds: [Int])?
            func search(_ start: Int, _ left: Int, _ acc: [Int], _ cost: Double) {
                if left == 1 {
                    guard n - start >= styleMinGroup else { return }
                    let c = cost + sse(start, n)
                    if best == nil || c < best!.cost { best = (c, acc + [n]) }
                    return
                }
                var end = start + styleMinGroup
                while end <= n - styleMinGroup * (left - 1) {
                    search(end, left - 1, acc + [end], cost + sse(start, end))
                    end += 1
                }
            }
            search(0, k, [0], 0)
            guard let found = best else { break }
            let newFit = 1 - found.cost / total
            let medians = zip(found.bounds, found.bounds.dropFirst()).map { median(Array(v[$0..<$1])) }
            let separated = zip(medians, medians.dropFirst()).allSatisfy { $1 - $0 >= minGap }
            guard newFit - fit >= styleMinGain, separated else { break }
            bounds = found.bounds
            fit = newFit
        }
        return zip(bounds, bounds.dropFirst()).map { Array(order[$0..<$1]) }
    }

    static func median(_ values: [Double]) -> Double {
        let s = values.sorted()
        guard !s.isEmpty else { return 0 }
        return (s[(s.count - 1) / 2] + s[s.count / 2]) / 2
    }
}
