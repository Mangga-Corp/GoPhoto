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

    /// Runs both requests on one upright frame. nil = nobody found.
    /// Only the largest person is used; anyone else in the frame is ignored.
    func detect(in pixelBuffer: CVPixelBuffer) -> PersonDetection? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform(includeOutline ? [boxRequest, faceRequest, maskRequest] : [boxRequest, faceRequest])
        } catch {
            return nil
        }

        guard let largest = boxRequest.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return nil
        }

        // Vision's origin is BOTTOM-left; SwiftUI's is TOP-left → flip Y
        let b = largest.boundingBox
        let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)

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
