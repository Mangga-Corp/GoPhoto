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
import CoreImage
import CoreImage.CIFilterBuiltins

/// Result for one camera frame.
nonisolated struct PersonDetection: @unchecked Sendable {
    /// Box around the person (normalized 0...1, origin TOP-LEFT). Used for alignment, not drawn.
    let box: CGRect
    /// White ring around the body (with a gap) on a transparent background. Covers the whole frame.
    let outline: CGImage?
}

nonisolated final class PersonDetector {

    // Where the person is (for alignment)
    private let boxRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }()

    // The person's shape (for drawing)
    private let maskRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced                 // made for video; try .fast if it lags
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private let ciContext = CIContext()

    // Outline look, as a fraction of the mask's width
    private let gapRatio: CGFloat = 0.025   // space between body and line
    private let lineRatio: CGFloat = 0.012  // line thickness

    /// Runs both requests on one upright frame. nil = nobody found.
    func detect(in pixelBuffer: CVPixelBuffer) -> PersonDetection? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([boxRequest, maskRequest])   // one pass, two answers
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

        let outline = maskRequest.results?.first.flatMap { makeOutline(from: $0.pixelBuffer) }
        return PersonDetection(box: box, outline: outline)
    }

    // MARK: - Mask → ring with a gap

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
