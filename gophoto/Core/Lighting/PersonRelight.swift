//
//  PersonRelight.swift
//  gophoto
//
//  Core layer: brightens only the people in a photo. A backlit face is dark, but raising the
//  camera's exposure would also wash out the background, so the lift is applied afterwards: the
//  segmentation model finds the people on a small copy, and the mask is scaled up to the full photo
//  so the result keeps the camera's full resolution.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit

nonisolated enum PersonRelight {

    /// The segmentation model, loaded once and shared.
    static let segmenter = DETRSegmenter()

    /// Lifts smaller than this (EV) are not worth the processing.
    static let minLift = 0.1

    /// Long edge of the copy the model looks at; the model itself works at a fixed small size.
    private static let maskSourceLongEdge: CGFloat = 640
    /// Mask edge softness, as a share of the photo's long edge.
    private static let featherShare: CGFloat = 0.003
    /// Long edge of the photo copy that guides the mask edges.
    private static let guideLongEdge: CGFloat = 1024
    /// Photographic stops of light for one unit of `lift`: `lift` is measured on the frame's encoded
    /// brightness, which is roughly the light raised to 1 / 2.2.
    private static let stopsPerLift = 2.2
    /// How far the mask is pulled inside the person's outline, in pixels of the guide copy, so the
    /// bright background right at the edge is not lifted with them (no halo).
    private static let erosionGuidePixels: CGFloat = 2

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The photo with every person lifted by `lift` EV and the rest untouched, same pixel size.
    /// Nil when nobody was found or anything failed: the caller keeps the original.
    /// Heavy: call off the main actor.
    static func relit(_ photo: CGImage, lift: Double, using segmenter: any SemanticSegmenting = segmenter) async -> CGImage? {
        guard lift >= minLift else { return nil }
        let image = CIImage(cgImage: photo)
        guard let small = smallCopy(of: image),
              let map = try? await segmenter.segment(small),
              let mask = personMask(from: map, guideImage: image, fullSize: image.extent.size) else { return nil }

        // Scaling the light (a plain exposure change) keeps every pixel's colour ratios, so skin and
        // clothes keep their own colour. Highlights are held back so nothing already bright clips.
        let lifted = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: lift * stopsPerLift])
        guard let weight = shadowWeight(of: image),
              let weighted = CIFilter(name: "CIMultiplyCompositing",
                                      parameters: [kCIInputImageKey: mask, kCIInputBackgroundImageKey: weight])?.outputImage
        else { return nil }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = lifted
        blend.backgroundImage = image
        blend.maskImage = weighted
        guard let output = blend.outputImage?.cropped(to: image.extent) else { return nil }

        return context.createCGImage(output, from: image.extent, format: .RGBA8,
                                     colorSpace: photo.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// The camera file with the people lifted by `lift` EV: the same photo, full resolution, with
    /// the original's metadata. Nil when nothing was changed (no lift, nobody found, failure).
    /// Heavy: runs off the main actor.
    static func relitFile(_ data: Data, lift: Double) async -> Data? {
        guard lift >= minLift else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let upright = CapturedPhotoEnhancing.uprightImage(from: data),
                  let photo = upright.cgImage,
                  let relit = await relit(photo, lift: lift) else { return nil }
            return CapturedPhotoEnhancing.file(for: UIImage(cgImage: relit), metadataFrom: data, quality: 0.95)
        }.value
    }

    /// How much of the lift each pixel takes, from its own brightness: all of it in the shadows and
    /// mid-tones, fading to none in the highlights.
    private static func shadowWeight(of image: CIImage) -> CIImage? {
        let luma = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
        ])
        let curve = CIFilter.toneCurve()
        curve.inputImage = luma
        curve.point0 = CGPoint(x: 0, y: 1)
        curve.point1 = CGPoint(x: 0.15, y: 1)
        curve.point2 = CGPoint(x: 0.4, y: 0.5)
        curve.point3 = CGPoint(x: 0.7, y: 0.1)
        curve.point4 = CGPoint(x: 1, y: 0)
        return curve.outputImage
    }

    private static func smallCopy(of image: CIImage) -> CGImage? {
        let scale = min(1, maskSourceLongEdge / max(image.extent.width, image.extent.height))
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
