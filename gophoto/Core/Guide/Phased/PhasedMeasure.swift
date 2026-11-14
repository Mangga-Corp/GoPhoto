//
//  PhasedMeasure.swift
//  gophoto
//
//  Phased guide: the measurements, as pure functions (unit-testable). Frame units are
//  normalized 0...1 with the origin top-left, like `PersonDetector`.
//
//  Assumptions (see Parameters.md): pinhole camera, eyes 40% down the face box (same rule as the
//  reference analysis), body proportions only where a landmark is hidden (marked "estimated").
//
import CoreGraphics
import Foundation

nonisolated enum PhasedMeasure {

    /// A box edge closer than this to the frame edge counts as touching it.
    static let edge = 0.012
    /// Eyes sit about 40% down a face rectangle (same rule as the photo analysis).
    static let eyeFraction = 0.40
    /// Typical hip→knee / shoulder→hip ratio (anthropometric tables ≈ 0.245 H / 0.288 H).
    static let kneeFromHips = 0.85
    /// Typical shoulder→hip / nose→shoulder ratio, used only when the hips are hidden.
    static let hipsFromShoulders = 2.6
    /// Shoulders→hips / head top→shoulders (≈ 0.29 H / 0.18 H): half shot with the hips hidden (table).
    static let hipsFromHeadShoulders = 1.6
    /// Shoulders→knees / head top→shoulders (≈ 0.53 H / 0.18 H): 3/4 without knees and hips.
    static let kneesFromHeadShoulders = 2.9
    /// Last resort with no usable joints (side view), the whole person in the mask: head top→knees
    /// ≈ 0.72 H, head top→hips ≈ 0.48 H (knee height ≈ 0.28 H, hip joint ≈ 0.52 H).
    static let kneesOfBody = 0.72
    static let hipsOfBody = 0.48

    enum SpanQuality: String, Sendable, Equatable {
        /// Both ends seen.
        case measured
        /// The lower end comes from body proportions (landmark hidden, e.g. knees under a dress).
        case estimated
        /// One end is cut by the frame: the real span is at least this.
        case lowerBound
    }

    struct Span: Sendable, Equatable {
        var value: Double
        var top: Double
        /// Where the span ends: feet / hem (full), knees (3/4), hips (half).
        var bottom: Double
        var quality: SpanQuality
        var cutTop: Bool
        var cutBottom: Bool
        var source: String
    }

    private static func meanY(_ landmarks: [BodyLandmark], _ joints: [BodyJoint]) -> Double? {
        let ys = landmarks.filter { joints.contains($0.joint) }.map { Double($0.point.y) }
        return ys.isEmpty ? nil : ys.reduce(0, +) / Double(ys.count)
    }

    /// The subject's span for `shot`. Full body uses the person's visual extent (the instance mask:
    /// hair and clothes included; the box when there is no mask). Joints that are not visible are
    /// not treated as cut: the mask touching an edge is the clipping signal.
    static func span(_ s: SubjectObservation, shot: PhasedShot) -> Span? {
        // A mask touching all four edges while the person box does not is not a reading of this
        // person (guard against a broken mask): use the box.
        let maskUsable = s.extent != nil && s.touches != [.top, .bottom, .left, .right]
        let extent = maskUsable ? s.extent! : s.box
        let usesMask = maskUsable
        let top = Double(min(extent.minY, s.box.minY))
        let touches = maskUsable ? s.touches : []
        let cutTop = touches.contains(.top) || top <= edge
        switch shot {
        case .full:
            let bottom = Double(max(extent.maxY, usesMask ? extent.maxY : s.box.maxY))
            let cutBottom = touches.contains(.bottom) || bottom >= 1 - edge
            let quality: SpanQuality = cutTop || cutBottom ? .lowerBound : .measured
            return Span(value: bottom - top, top: top, bottom: bottom, quality: quality,
                        cutTop: cutTop, cutBottom: cutBottom, source: usesMask ? "mask" : "box")
        case .threeQuarter, .half:
            // No pose (side view: the skeleton often fails) still leaves the mask fallbacks below.
            let marks = s.landmarks ?? []
            let shoulders = meanY(marks, [.leftShoulder, .rightShoulder]) ?? meanY(marks, [.neck])
            // The whole person in the mask (neither end cut): body height for a last-resort estimate.
            let wholeBody: Double? = usesMask && !cutTop && !touches.contains(.bottom)
                && Double(extent.maxY) < 1 - edge ? Double(extent.maxY) - top : nil
            let hips = meanY(marks, [.leftHip, .rightHip, .root])
            let frameBottomCut = touches.contains(.bottom) || Double(extent.maxY) >= 1 - edge
            var bottom: Double?
            var quality = SpanQuality.measured
            var source = ""
            if shot == .threeQuarter {
                if let knees = meanY(marks, [.leftKnee, .rightKnee]) {
                    bottom = knees; source = "knees"
                } else if let hips, let shoulders, hips > shoulders {
                    bottom = hips + kneeFromHips * (hips - shoulders); quality = .estimated
                    source = "knees est. from hips"
                } else if let hs = headAndShoulders(s) {
                    // Head top → shoulders ≈ 0.18 H, shoulders → knees ≈ 0.53 H.
                    bottom = hs.shoulders + kneesFromHeadShoulders * (hs.shoulders - hs.top); quality = .estimated
                    source = "knees est. from head + shoulders"
                } else if let wholeBody {
                    bottom = top + kneesOfBody * wholeBody; quality = .estimated
                    source = "knees est. from body height"
                }
            } else {
                if let hips {
                    bottom = hips; source = "hips"
                } else if let hs = headAndShoulders(s) {
                    // Head top → shoulders ≈ 0.18 H, shoulders → hips ≈ 0.29 H (anthropometric tables).
                    bottom = hs.shoulders + hipsFromHeadShoulders * (hs.shoulders - hs.top); quality = .estimated
                    source = "hips est. from head + shoulders"
                } else if let shoulders, let nose = meanY(marks, [.nose]), shoulders > nose {
                    bottom = shoulders + hipsFromShoulders * (shoulders - nose); quality = .estimated
                    source = "hips est. from shoulders"
                } else if let wholeBody {
                    bottom = top + hipsOfBody * wholeBody; quality = .estimated
                    source = "hips est. from body height"
                }
            }
            guard let bottom else { return nil }
            if cutTop { quality = .lowerBound }
            return Span(value: bottom - top, top: top, bottom: bottom, quality: quality,
                        cutTop: cutTop, cutBottom: frameBottomCut && bottom > 1, source: source)
        }
    }

    // MARK: Vantage

    struct Vantage: Sendable, Equatable {
        /// Eyes below the horizon, in face heights (+ = camera above the eyes).
        var faces: Double
        /// Camera above the eyes, degrees.
        var degrees: Double
    }

    /// Camera height against the subject's eyes. The horizon (the camera's own height) sits
    /// `f·tan(pitch)` above the frame centre; the eyes' distance below it over the face height does
    /// not change with walking closer or farther, nor with tilting (pitch is measured).
    static func vantage(face: CGRect, pitch: Double, verticalFOV: Double) -> Vantage? {
        vantage(eyeY: Double(face.minY) + Double(face.height) * eyeFraction, faceHeight: Double(face.height),
                pitch: pitch, verticalFOV: verticalFOV)
    }

    static func vantage(eyeY: Double, faceHeight: Double, pitch: Double, verticalFOV: Double) -> Vantage? {
        guard verticalFOV > 0, faceHeight > 0 else { return nil }
        let focal = 0.5 / tan(verticalFOV * .pi / 360)
        let eyeAboveAxis = atan((0.5 - eyeY) / focal) * 180 / .pi
        let horizonY = 0.5 - focal * tan(pitch * .pi / 180)
        return Vantage(faces: (eyeY - horizonY) / faceHeight, degrees: pitch - eyeAboveAxis)
    }

    // MARK: Head from pose (no face: back turned, face hidden)

    /// Eyes sit 2/5 of the way down from the head top to the shoulder line (Reynard).
    static let headEyeFraction = 0.40
    /// A face box ≈ 0.55 × (head top → shoulder line): head top→shoulders ≈ 32 cm, face box
    /// (brow→chin) ≈ 18 cm. Only scales the "faces" unit; degrees do not use it.
    static let headFaceRatio = 0.55

    struct Head: Sendable, Equatable {
        var eyeY: Double
        /// Estimated face box height (frame units).
        var faceHeight: Double
    }

    /// The shoulder line: the mean of the shoulders seen, else the neck joint (Vision places it
    /// between the shoulders). The most consistent joints: front, side and back, and above a table.
    static func shoulderLine(_ marks: [BodyLandmark]) -> Double? {
        meanY(marks, [.leftShoulder, .rightShoulder]) ?? meanY(marks, [.neck])
    }

    /// Eyes not read (back turned, looking down, side): neither eye joint, while the shoulders read.
    static func eyesUnseen(_ s: SubjectObservation) -> Bool {
        guard let marks = s.landmarks, shoulderLine(marks) != nil else { return false }
        return !marks.contains { $0.joint == .leftEye || $0.joint == .rightEye }
    }

    /// Head top from the person's mask, with the shoulder line below it. Nil when the mask is cut at
    /// the top, the shoulders are missing, or a hand/elbow is above the shoulders (raised arms move
    /// the mask top off the head).
    static func headAndShoulders(_ s: SubjectObservation) -> (top: Double, shoulders: Double)? {
        guard let extent = s.extent, !s.touches.contains(.top), let marks = s.landmarks,
              let shoulders = shoulderLine(marks) else { return nil }
        let arms: Set<BodyJoint> = [.leftWrist, .rightWrist, .leftElbow, .rightElbow]
        if marks.contains(where: { arms.contains($0.joint) && Double($0.point.y) < shoulders }) { return nil }
        let top = Double(extent.minY)
        guard shoulders - top > 0.01 else { return nil }
        return (top, shoulders)
    }

    /// The eye line without eyes: 2/5 of the way from the head top to the shoulder line (Reynard;
    /// head top→eyes ≈ 0.07 H, head top→shoulders ≈ 0.18 H → 0.38).
    static func head(_ s: SubjectObservation) -> Head? {
        guard let hs = headAndShoulders(s) else { return nil }
        let span = hs.shoulders - hs.top
        return Head(eyeY: hs.top + span * headEyeFraction, faceHeight: span * headFaceRatio)
    }

    // MARK: Final framing

    /// Smallest linear crop scale that still gives `floorMP` out of a `sourceMP` photo.
    static func cropMinScale(sourceMP: Double?, floorMP: Double) -> Double {
        guard let sourceMP, sourceMP > 0 else { return 1 }
        return min(1, sqrt(floorMP / sourceMP))
    }

    struct Crop: Sendable, Equatable {
        /// Frame units, origin top-left, same aspect as the frame.
        var rect: CGRect
        /// The crop had to be moved to stay inside the frame (vertical / horizontal), frame units.
        var verticalShift: Double
        var horizontalShift: Double
        /// The crop had to be made larger than the reference asks for (quality floor).
        var floorLimited: Bool
    }

    /// The crop that puts the subject where the reference has it: height `c = r` (the subject's span
    /// then fills the reference span), clamped to `[minScale, 1]`, top aligned to the reference top.
    /// `shape`: the photo's shape and the band it must stay in. Its width is `c × widthFactor`, and
    /// `minScale` (the quality floor of a full-frame-shaped crop) grows so a narrower crop keeps the
    /// same pixel count. `.fullFrame` is the original 3:4 crop.
    static func crop(span: Span, subjectMidX: Double, target: PhasedTarget, minScale: Double,
                     shape: PhasedCropShape = .fullFrame) -> Crop? {
        guard let refSpan = target.span, refSpan > 0 else { return nil }
        let refTop = target.top ?? 0.05, refMid = target.midX ?? 0.5
        let k = min(1, max(0.01, shape.widthFactor))
        let floor = shapeMinScale(minScale, shape: shape)
        let raw = span.value / refSpan
        let c = min(1, max(floor, raw))
        let width = c * k
        let wantTop = span.top - refTop * c
        let wantLeft = subjectMidX - refMid * width
        let top = min(max(wantTop, 0), 1 - c)
        let left = min(max(wantLeft, shape.minX), max(shape.minX, shape.maxX - width))
        return Crop(rect: CGRect(x: left, y: top, width: width, height: c),
                    verticalShift: wantTop - top, horizontalShift: wantLeft - left,
                    floorLimited: raw < floor)
    }

    /// The crop-height floor for `shape`: a crop `widthFactor` as wide needs `1/√widthFactor` the
    /// height scale for the same pixel count. Equal to `minScale` for the full frame.
    static func shapeMinScale(_ minScale: Double, shape: PhasedCropShape) -> Double {
        let k = min(1, max(0.01, shape.widthFactor))
        return min(1, minScale / sqrt(k))
    }

    /// Whether `crop` (frame units, frame aspect width:height = `aspect`) still lies inside the
    /// frame after rotating the image by `degrees` about the crop's centre.
    static func fitsRotated(_ crop: CGRect, degrees: Double, aspect: Double) -> Bool {
        let a = degrees * .pi / 180
        let cx = Double(crop.midX) * aspect, cy = Double(crop.midY)
        let hw = Double(crop.width) * aspect / 2, hh = Double(crop.height) / 2
        for (dx, dy) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)] {
            let x = cx + dx * cos(a) - dy * sin(a)
            let y = cy + dx * sin(a) + dy * cos(a)
            if x < 0 || x > aspect || y < 0 || y > 1 { return false }
        }
        return true
    }
}
