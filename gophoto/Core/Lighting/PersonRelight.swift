//
//  PersonRelight.swift
//  gophoto
//
//  Core layer: brightens only the people in a backlit photo, like a fill light would. Raising the
//  camera's exposure would wash out the background, so the photo is taken normally (with all of the
//  camera's own processing) and the people are lifted afterwards, at full resolution.
//
//  Natural colour: the whole person gets one gain on the light itself (multiply in linear light),
//  which is what extra light falling on them does. Each pixel keeps its colour ratios, and the
//  texture and contrast inside the person stay as they were.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import UIKit
import Vision

nonisolated enum PersonRelight {

    /// Lifts smaller than this (units of `BacklightController.lift`) are not worth the processing.
    static let minLift = 0.1
    /// Photographic stops for one unit of lift: the lift is measured on the frame's encoded
    /// brightness, which is roughly the light raised to 1 / 2.2.
    private static let stopsPerLift = 2.2
    /// Most light added, stops. More looks pasted on: the person no longer matches the scene.
    private static let maxStops = 1.2
    /// Mask edge softness, as a share of the photo's long edge.
    private static let featherShare: CGFloat = 0.0015

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Stops of light to add for a lift.
    static func stops(forLift lift: Double) -> Double {
        min(lift * stopsPerLift, maxStops)
    }

    /// The camera file with the people lifted: the same photo, full resolution, with the original's
    /// metadata. Nil when nothing was changed (no lift, nobody found, failure). Heavy: off the main actor.
    static func relitFile(_ data: Data, lift: Double) async -> Data? {
        guard lift >= minLift else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> Data? in
            guard let upright = CapturedPhotoEnhancing.uprightImage(from: data),
                  let photo = upright.cgImage,
                  let relit = relit(photo, lift: lift) else { return nil }
            return CapturedPhotoEnhancing.file(for: UIImage(cgImage: relit), metadataFrom: data, quality: 0.95)
        }.value
    }

    /// The photo with every person lifted by `stops(forLift:)` and the rest untouched, same size.
    /// Nil when nobody was found or anything failed.
    static func relit(_ photo: CGImage, lift: Double) -> CGImage? {
        guard lift >= minLift else { return nil }
        let image = CIImage(cgImage: photo)
        guard let mask = personMask(for: photo, size: image.extent.size) else { return nil }

        let lifted = image
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: stops(forLift: lift)])
            .applyingFilter("CIColorClamp")      // keep within 0...1 before the file is written
        let blend = CIFilter.blendWithMask()
        blend.inputImage = lifted
        blend.backgroundImage = image
        blend.maskImage = mask
        guard let output = blend.outputImage?.cropped(to: image.extent) else { return nil }

        return context.createCGImage(output, from: image.extent, format: .RGBA8,
                                     colorSpace: photo.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB))
    }

    /// Soft matte of the people (Vision's person segmentation, accurate level: made for people,
    /// down to the hair), scaled to the photo. Nil when no one is in it.
    private static func personMask(for photo: CGImage, size: CGSize) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? VNImageRequestHandler(cgImage: photo).perform([request])
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }

        let matte = CIImage(cvPixelBuffer: buffer)
        guard matte.extent.width > 0, hasPerson(matte) else { return nil }
        let scaled = matte.samplingLinear()
            .transformed(by: CGAffineTransform(scaleX: size.width / matte.extent.width,
                                               y: size.height / matte.extent.height))
            .clampedToExtent()
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = scaled
        blur.radius = Float(max(size.width, size.height) * featherShare)
        return blur.outputImage?.cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Vision always returns a matte; an empty one means nobody was found.
    private static func hasPerson(_ matte: CIImage) -> Bool {
        let filter = CIFilter.areaMaximum()
        filter.inputImage = matte
        filter.extent = matte.extent
        guard let output = filter.outputImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return pixel[0] > 128
    }
}
