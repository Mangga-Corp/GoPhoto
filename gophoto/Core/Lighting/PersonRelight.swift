//
//  PersonRelight.swift
//  gophoto
//
//  Core layer: makes backlit people brighter without touching the background. Brightening a
//  finished photo cannot work: the camera has already thrown away the colour in the dark parts, so
//  skin turns grey. Instead the camera takes a bracket (one normal frame, one exposed brighter for
//  the people) and this puts the people from the bright frame onto the normal one. The colours are
//  what the sensor really saw, at full resolution. The segmentation model finds the people.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit
import Vision

nonisolated enum PersonRelight {

    /// The segmentation model, loaded once and shared.
    static let segmenter = DETRSegmenter()

    /// Lifts smaller than this (units of `BacklightController.lift`) are not worth a bracket.
    static let minLift = 0.1
    /// Photographic stops for one unit of lift: the lift is measured on the frame's encoded
    /// brightness, which is roughly the light raised to 1 / 2.2.
    private static let stopsPerLift = 2.2
    /// Most the bright frame is pushed above the normal one, stops.
    private static let maxBracketStops = 2.0

    /// Long edge of the copy the model looks at; the model itself works at a fixed small size.
    private static let maskSourceLongEdge: CGFloat = 640
    /// Long edge of the copies used to line the two frames up.
    private static let alignLongEdge: CGFloat = 1024
    /// Mask edge softness, as a share of the photo's long edge.
    private static let featherShare: CGFloat = 0.003
    /// Long edge of the photo copy that guides the mask edges.
    private static let guideLongEdge: CGFloat = 1024
    /// How far the mask is pulled inside the person's outline, in pixels of the guide copy: the
    /// bright frame's background right at the edge is overexposed and must not show (no halo).
    private static let erosionGuidePixels: CGFloat = 2

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Exposure bias for the bright frame of the bracket, stops; nil when no bracket is needed.
    static func bracketBias(forLift lift: Double) -> Float? {
        guard lift >= minLift else { return nil }
        return Float(min(lift * stopsPerLift, maxBracketStops))
    }

    /// The normal camera file with the people taken from the bright frame: same size, the normal
    /// file's metadata. Nil when nobody was found or anything failed: the caller keeps the normal file.
    /// Heavy: runs off the main actor.
    static func compositeFile(normal: Data, people: Data, bias: Float) async -> Data? {
        await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let normalImage = CapturedPhotoEnhancing.uprightImage(from: normal)?.cgImage,
                  let peopleImage = CapturedPhotoEnhancing.uprightImage(from: people)?.cgImage,
                  let result = await composite(normal: normalImage, people: peopleImage, bias: bias) else { return nil }
            return CapturedPhotoEnhancing.file(for: UIImage(cgImage: result), metadataFrom: normal, quality: 0.95)
        }.value
    }

    /// `normal` with the people replaced by the same people from `people` (the frame taken `bias`
    /// stops brighter), lined up first in case the phone moved between the two frames.
    static func composite(normal: CGImage, people: CGImage, bias: Float,
                          using segmenter: any SemanticSegmenting = segmenter) async -> CGImage? {
        let base = CIImage(cgImage: normal)
        let bright = CIImage(cgImage: people)
        guard base.extent.size == bright.extent.size,
              let small = smallCopy(of: bright, longEdge: maskSourceLongEdge),
              let map = try? await segmenter.segment(small),
              let mask = personMask(from: map, guideImage: bright, fullSize: bright.extent.size) else { return nil }

        let shift = offset(of: bright, onto: base, bias: bias) ?? .identity
        let blend = CIFilter.blendWithMask()
        blend.inputImage = bright.transformed(by: shift)
        blend.backgroundImage = base
        blend.maskImage = mask.transformed(by: shift)
        guard let output = blend.outputImage?.cropped(to: base.extent) else { return nil }

        return context.createCGImage(output, from: base.extent, format: .RGBA8,
                                     colorSpace: normal.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The shift (full-size pixels) that lines `moving` up with `reference`. The bright frame is
    /// darkened back first so both look alike to the registration. Nil when it could not be measured.
    private static func offset(of moving: CIImage, onto reference: CIImage, bias: Float) -> CGAffineTransform? {
        let darkened = moving.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -bias])
        guard let referenceSmall = smallCopy(of: reference, longEdge: alignLongEdge),
              let movingSmall = smallCopy(of: darkened, longEdge: alignLongEdge) else { return nil }
        let request = VNTranslationalImageRegistrationRequest(targetedCGImage: movingSmall)
        try? VNImageRequestHandler(cgImage: referenceSmall).perform([request])
        guard let shift = (request.results?.first as? VNImageTranslationAlignmentObservation)?.alignmentTransform
        else { return nil }
        let scale = reference.extent.width / CGFloat(referenceSmall.width)
        return CGAffineTransform(translationX: shift.tx * scale, y: shift.ty * scale)
    }

    private static func smallCopy(of image: CIImage, longEdge: CGFloat) -> CGImage? {
        let scale = min(1, longEdge / max(image.extent.width, image.extent.height))
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(scaled, from: scaled.extent)
    }

    /// A white-on-black mask of the people, at the full photo's size, with soft edges. nil if no one.
    private static func personMask(from map: SegmentationMap, guideImage: CIImage, fullSize: CGSize) -> CIImage? {
        var bytes = [UInt8](repeating: 0, count: map.width * map.height)
        var found = false
        for y in 0..<map.height {
            for x in 0..<map.width where map.groups[y * map.width + x] == .person {
                bytes[y * map.width + x] = 255
                found = true
            }
        }
        guard found else { return nil }

        let small = CIImage(bitmapData: Data(bytes), bytesPerRow: map.width,
                            size: CGSize(width: map.width, height: map.height), format: .L8, colorSpace: nil)
        let fullRect = CGRect(origin: .zero, size: fullSize)

        // Snap the mask's edges to the photo's own edges: upsample it guided by a mid-size copy of
        // the photo, then scale that up to full size.
        let guideScale = guideLongEdge / max(fullSize.width, fullSize.height)
        let guide = guideImage.transformed(by: CGAffineTransform(scaleX: guideScale, y: guideScale))
        let half = CGAffineTransform(scaleX: guide.extent.width / 2 / CGFloat(map.width),
                                     y: guide.extent.height / 2 / CGFloat(map.height))
        let upsample = CIFilter.edgePreserveUpsample()
        upsample.inputImage = guide
        upsample.smallImage = small.samplingLinear().transformed(by: half)
        upsample.spatialSigma = 3
        upsample.lumaSigma = 0.1
        let eroded = (upsample.outputImage ?? small).applyingFilter("CIMorphologyMinimum",
                                                                    parameters: [kCIInputRadiusKey: erosionGuidePixels])
        let refined = eroded
            .samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: fullSize.width / guide.extent.width,
                                               y: fullSize.height / guide.extent.height))
            .clampedToExtent()

        // Soften slightly, then steepen around 50% so the edge is smooth but tight.
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = refined
        blur.radius = Float(max(fullSize.width, fullSize.height) * featherShare)
        let curve = CIFilter.toneCurve()
        curve.inputImage = blur.outputImage
        curve.point0 = CGPoint(x: 0, y: 0)
        curve.point1 = CGPoint(x: 0.35, y: 0.05)
        curve.point2 = CGPoint(x: 0.5, y: 0.5)
        curve.point3 = CGPoint(x: 0.65, y: 0.95)
        curve.point4 = CGPoint(x: 1, y: 1)
        return curve.outputImage?.cropped(to: fullRect)
    }
}
