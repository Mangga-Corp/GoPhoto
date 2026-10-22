//
//  PersonDetector.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 11/10/26.
//
//
//  PersonDetector.swift
//  gophoto
//
//  Core layer: the ONLY place that uses Apple's Vision framework.
//  Input: one camera frame. Output: where the person is.
//
import Vision
import CoreVideo
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Result for one camera frame: ONE person (the largest), never more.
nonisolated struct PersonDetection: @unchecked Sendable {
    /// Box around the person (normalized 0...1, origin TOP-LEFT). Used for alignment.
    let box: CGRect
    /// Face of that person (normalized, origin TOP-LEFT), when Vision found one inside the box.
    var face: CGRect? = nil
    /// Vertical field of view of the upright frame, degrees (set by `CameraService`).
    var verticalFOV: Double? = nil
    /// Largest photo the camera can take, megapixels (set by `CameraService`).
    var photoMegapixels: Double? = nil
    /// White ring around the body on a transparent background, covering the whole frame.
    /// Only made when `PersonDetector.includeOutline` is on (guide mode "A · Old look").
    var outline: CGImage? = nil
}

nonisolated final class PersonDetector {

    // Where the person is (for alignment)
    private let boxRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }()

    // The person's face (eye line and head size for the camera-height and distance guide)
    private let faceRequest = VNDetectFaceRectanglesRequest()

    /// Draw the body outline too (costly: person segmentation every frame). Old-look mode only.
    var includeOutline = false

    // The person's shape (for the old-look outline)
    private let maskRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private let ciContext = CIContext()

    // Outline look, as a fraction of the mask's width
    private let gapRatio: CGFloat = 0.025   // space between body and line
    private let lineRatio: CGFloat = 0.012  // line thickness

    // Subject lock: once a person is chosen, follow THAT person (box overlap) instead of
    // re-picking the largest every frame, so the guide never jumps to someone else.
    private var lockedBox: CGRect?
    private var missedFrames = 0
    /// Detection frames the locked person may be missing before another person can be chosen.
    private let maxMissedFrames = 15
    private let minOverlap: CGFloat = 0.15

    /// Forget the locked person (the next detection picks the largest again).
    func resetSubjectLock() {
        lockedBox = nil
        missedFrames = 0
    }

    /// Runs the requests on one upright frame. nil = nobody found (or the locked person is
    /// briefly hidden). Only one person is used; anyone else in the frame is ignored.
    func detect(in pixelBuffer: CVPixelBuffer) -> PersonDetection? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform(includeOutline ? [boxRequest, faceRequest, maskRequest] : [boxRequest, faceRequest])
        } catch {
            return nil
        }

        // Vision's origin is BOTTOM-left; SwiftUI's is TOP-left → flip Y
        let boxes = (boxRequest.results ?? []).map { r -> CGRect in
            let b = r.boundingBox
            return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        }

        let box: CGRect
        if let locked = lockedBox,
           let best = boxes.max(by: { Self.overlap($0, locked) < Self.overlap($1, locked) }),
           Self.overlap(best, locked) >= minOverlap {
            box = best                                   // same person as before
        } else if lockedBox != nil, missedFrames < maxMissedFrames {
            missedFrames += 1                            // locked person hidden for a moment: wait
            return nil
        } else if let largest = boxes.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            box = largest                                // first person, or the old one is gone
        } else {
            lockedBox = nil
            return nil
        }
        lockedBox = box
        missedFrames = 0

        // Largest face whose centre lies inside that person's box
        let face = faceRequest.results?
            .map { f -> CGRect in
                let r = f.boundingBox
                return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
            }
            .filter { box.contains(CGPoint(x: $0.midX, y: $0.midY)) }
            .max { $0.height < $1.height }

        let outline = includeOutline ? maskRequest.results?.first.flatMap { makeOutline(from: $0.pixelBuffer) } : nil
        return PersonDetection(box: box, face: face, outline: outline)
    }

    /// Intersection over union of two boxes (0 = apart, 1 = identical).
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    // MARK: - Mask → ring with a gap (old look)

    private func makeOutline(from mask: CVPixelBuffer) -> CGImage? {
        let maskImage = CIImage(cvPixelBuffer: mask)
        let extent = maskImage.extent
        let gap = extent.width * gapRatio
        let line = extent.width * lineRatio

        // 1. Soften jagged edges
        let smooth = maskImage.clampedToExtent().applyingGaussianBlur(sigma: 2)

        // 2. Grow the body shape: once by the gap, once by gap + line
        let inner = grow(smooth, by: gap)
        let outer = grow(smooth, by: gap + line)

        // 3. Outer minus inner = a ring floating around the body
        let subtract = CIFilter.subtractBlendMode()
        subtract.inputImage = inner
        subtract.backgroundImage = outer
        guard let ring = subtract.outputImage?.cropped(to: extent) else { return nil }

        // 4. White → visible, black → transparent
        let toAlpha = CIFilter.maskToAlpha()
        toAlpha.inputImage = ring
        guard let output = toAlpha.outputImage else { return nil }

        return ciContext.createCGImage(output, from: extent)
    }

    /// "Grows" white areas outward by `radius` pixels (called dilation).
    private func grow(_ image: CIImage, by radius: CGFloat) -> CIImage {
        let filter = CIFilter.morphologyMaximum()
        filter.inputImage = image
        filter.radius = Float(radius)
        return filter.outputImage ?? image
    }
}
