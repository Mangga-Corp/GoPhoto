//
//  EdgeClutter.swift
//  gophoto
//
//  Background-clutter metric for the automatic lens switch. Pure and deterministic: it reads the
//  DETR class map (`SegmentationMap`) the preference analysis already uses, plus Vision's person
//  box. No model runs here.
//

import CoreGraphics
import Foundation

/// A DETR class map taken from one live frame, with the person box and the zoom it belongs to.
nonisolated struct SceneSample: Sendable {
    let map: SegmentationMap
    /// Vision's person box for the same frame (normalized, top-left origin).
    let subjectBox: CGRect
    /// User-perceived zoom when the frame was taken (0.5, 1).
    let zoom: Double
    /// `systemUptime` when the sample was stored.
    let capturedAt: TimeInterval
}

/// What the left and right surroundings of the subject contain.
nonisolated struct EdgeClutterMetrics: Sendable, Equatable {
    /// Share of the measured pixels that are countable objects (car, chair, bottle...; people excluded).
    let objectCoverage: Double
    /// Share that belongs to a known surface (sky, wall, road, trees, water...). Not clutter.
    let surfaceCoverage: Double
    /// Share with a label this app does not interpret. Not counted as clutter or as clean.
    let unknownCoverage: Double
    /// Distinct object classes that each cover at least 2% of the measured pixels.
    let objectKinds: Int
    /// Sides (left, right) with enough pixels to judge: 0, 1 or 2.
    let measuredSides: Int
    /// Measured pixels as a share of the whole frame.
    let measuredArea: Double

    /// Enough pixels, enough sides and few enough unknown labels to trust the numbers.
    var isReliable: Bool {
        measuredSides >= 1 && measuredArea >= EdgeClutter.minimumMeasuredArea
            && unknownCoverage <= EdgeClutter.maximumUnknownCoverage
    }

    /// Object coverage above this is "busy". A user whose reference photos have object-rich
    /// surroundings gets a higher bar (1.5x their typical object share), never below the floor.
    static func threshold(preferredObjectShare: Double?) -> Double {
        guard let preferred = preferredObjectShare else { return EdgeClutter.baseObjectThreshold }
        return min(EdgeClutter.maximumObjectThreshold, max(EdgeClutter.baseObjectThreshold, preferred * 1.5))
    }

    /// Busy edges: many pixels are objects AND they are several different things. One big object
    /// (a parked car) or a plain surface is not clutter, and neither is a reliable-looking but
    /// unreadable region.
    func isSubstantial(preferredObjectShare: Double?) -> Bool {
        isReliable
            && objectCoverage >= Self.threshold(preferredObjectShare: preferredObjectShare)
            && objectKinds >= EdgeClutter.minimumObjectKinds
    }

    var summary: String {
        String(format: "object=%.2f surface=%.2f unknown=%.2f kinds=%d sides=%d area=%.2f",
               objectCoverage, surfaceCoverage, unknownCoverage, objectKinds, measuredSides, measuredArea)
    }
}

nonisolated enum EdgeClutter {
    static let subjectPadding = 0.02          // frame fraction kept clear around the person's box
    static let minimumSideArea = 0.02         // frame fraction a side needs to count as measured
    static let minimumMeasuredArea = 0.05
    static let maximumUnknownCoverage = 0.40
    static let baseObjectThreshold = 0.25
    static let maximumObjectThreshold = 0.60
    static let objectKindShare = 0.02
    static let minimumObjectKinds = 2

    private enum Kind { case object, surface, unknown, person }

    /// The part of a frame at `zoom` that stays visible at 1×: centred, `zoom` of each dimension.
    /// (The 0.5× view contains the 1× view as its central half.)
    static func wideViewCrop(zoom: Double) -> CGRect {
        let c = min(1, max(0.1, zoom))
        return CGRect(x: (1 - c) / 2, y: (1 - c) / 2, width: c, height: c)
    }

    /// Measures the surroundings left and right of the subject, outside the person's box and
    /// outside any person pixels. At the ultrawide zoom only the part a 1× view would drop (outside
    /// the central crop) is measured: that is the content the wider view adds.
    /// Returns nil when the map has no labels.
    static func measure(map: SegmentationMap, subject: CGRect, zoom: Double) -> EdgeClutterMetrics? {
        guard map.hasLabels, map.width > 0, map.height > 0 else { return nil }

        // One category per class index, so the pixel loop does no string work.
        let kinds: [Kind] = map.labels.map { label in
            if ObjectLabel.isPerson(label) { return .person }
            if ObjectLabel.isObject(label) { return .object }
            return SceneLabelGroup.group(forLabel: label) == .other ? .unknown : .surface
        }

        let left = Double(subject.minX) - subjectPadding
        let right = Double(subject.maxX) + subjectPadding
        let crop: CGRect? = zoom < 0.95 ? wideViewCrop(zoom: zoom) : nil

        var objects = 0, surfaces = 0, unknowns = 0, leftCells = 0, rightCells = 0
        var objectClassCounts: [Int32: Int] = [:]
        let w = map.width, h = map.height

        for y in 0..<h {
            let py = (Double(y) + 0.5) / Double(h)
            for x in 0..<w {
                let px = (Double(x) + 0.5) / Double(w)
                let isLeft = px < left, isRight = px > right
                guard isLeft || isRight else { continue }
                if let crop, crop.contains(CGPoint(x: px, y: py)) { continue }

                let index = map.classIndices[y * w + x]
                let i = Int(index)
                let kind: Kind = kinds.indices.contains(i) ? kinds[i] : .unknown
                if kind == .person { continue }
                if isLeft { leftCells += 1 } else { rightCells += 1 }
                switch kind {
                case .object: objects += 1; objectClassCounts[index, default: 0] += 1
                case .surface: surfaces += 1
                default: unknowns += 1
                }
            }
        }

        let total = Double(w * h)
        let measured = objects + surfaces + unknowns
        guard measured > 0 else {
            return EdgeClutterMetrics(objectCoverage: 0, surfaceCoverage: 0, unknownCoverage: 0, objectKinds: 0,
                                      measuredSides: 0, measuredArea: 0)
        }
        let m = Double(measured)
        let sides = (Double(leftCells) / total >= minimumSideArea ? 1 : 0)
            + (Double(rightCells) / total >= minimumSideArea ? 1 : 0)
        let kindCount = objectClassCounts.values.filter { Double($0) / m >= objectKindShare }.count
        return EdgeClutterMetrics(objectCoverage: Double(objects) / m, surfaceCoverage: Double(surfaces) / m,
                                  unknownCoverage: Double(unknowns) / m, objectKinds: kindCount,
                                  measuredSides: sides, measuredArea: m / total)
    }
}
