//
//  BackgroundBlurMeter.swift
//  gophoto
//
//  How blurred a photo's background is, relative to its person (version 18).
//  Ratio = background sharpness / person sharpness, sharpness = RMS of the Laplacian (fine
//  detail) on a ~1024 px grey copy. Measured inside one photo, so it survives the compression
//  and resizing of web references. ~1 = background as sharp as the person, ~0.2 = strong bokeh.
//  The person comes from Vision's person segmentation; a band around their edge is left out of
//  both regions (the outline itself is sharp detail and would count as "sharp background").
//
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import UIKit

nonisolated enum BackgroundBlurMeter {

    /// Long side the measurement runs at.
    static let side: CGFloat = 1024
    /// Band around the person's edge left out of both regions, fraction of the long side.
    static let edgeBand: CGFloat = 0.02
    /// Person sharper than this (mean Laplacian², grey 0...1) or the photo is skipped: a blurry
    /// person makes every ratio meaningless.
    static let minPersonEnergy = 1e-5

    private static let context = CIContext(options: [.workingFormat: CIFormat.RGBAf, .cacheIntermediates: false])

    /// Ratio per reference photo (`PhotoItem.id.uuidString` → ratio); photos without a usable
    /// person are left out.
    static func ratios(_ photos: [(id: UUID, image: UIImage)]) -> [String: Double] {
        var out: [String: Double] = [:]
        for photo in photos {
            guard let cg = upright(photo.image) else { continue }
            let image = CIImage(cgImage: cg)
            guard let mask = personMask(image), let r = ratio(image: image, personMask: mask) else { continue }
            out[photo.id.uuidString] = r
        }
        return out
    }

    /// Person mask (1 = person) at `image`'s size, or nil when nobody was found.
    static func personMask(_ image: CIImage) -> CIImage? {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do { try VNImageRequestHandler(ciImage: image, options: [:]).perform([request]) } catch { return nil }
        guard let buffer = request.results?.first?.pixelBuffer else { return nil }
        return fit(CIImage(cvPixelBuffer: buffer), to: image.extent)
    }

    /// Background / person sharpness. `personMask` is 1 on the person, at `image`'s extent.
    static func ratio(image: CIImage, personMask: CIImage) -> Double? {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scale = min(1, side / max(extent.width, extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let area = small.extent
        let mask = fit(personMask, to: area)

        // Grey, Laplacian, squared (CIColorPolynomial a2 = 1: x²), all in float.
        let grey = small.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
            "inputGVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
            "inputBVector": CIVector(x: 0.299, y: 0.587, z: 0.114, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        let laplacian = grey.clampedToExtent().applyingFilter("CIConvolution3X3", parameters: [
            "inputWeights": CIVector(values: [0, 1, 0, 1, -4, 1, 0, 1, 0], count: 9),
            "inputBias": 0]).cropped(to: area)
        let square = CIVector(x: 0, y: 0, z: 1, w: 0)
        let energy = laplacian.applyingFilter("CIColorPolynomial", parameters: [
            "inputRedCoefficients": square, "inputGreenCoefficients": square,
            "inputBlueCoefficients": square, "inputAlphaCoefficients": CIVector(x: 1, y: 0, z: 0, w: 0)])

        // Regions without the edge band: shrink the person, shrink the background.
        let band = Float(max(area.width, area.height) * edgeBand)
        let personCore = shrink(mask, by: band, in: area)
        let invert = CIFilter.colorInvert()
        invert.inputImage = mask
        guard let background = invert.outputImage else { return nil }
        let backgroundCore = shrink(background, by: band, in: area)

        let personShare = mean(personCore, area), backgroundShare = mean(backgroundCore, area)
        guard personShare > 0.02, backgroundShare > 0.05 else { return nil }
        let personEnergy = mean(multiply(energy, personCore), area) / personShare
        let backgroundEnergy = mean(multiply(energy, backgroundCore), area) / backgroundShare
        guard personEnergy >= minPersonEnergy, backgroundEnergy.isFinite else { return nil }
        return min(1.5, (backgroundEnergy / personEnergy).squareRoot())
    }

    // MARK: Helpers

    static func fit(_ mask: CIImage, to rect: CGRect) -> CIImage {
        let m = mask.extent
        guard m.width > 0, m.height > 0 else { return mask }
        return mask
            .transformed(by: CGAffineTransform(translationX: -m.minX, y: -m.minY))
            .transformed(by: CGAffineTransform(scaleX: rect.width / m.width, y: rect.height / m.height))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
            .cropped(to: rect)
    }

    private static func shrink(_ mask: CIImage, by radius: Float, in rect: CGRect) -> CIImage {
        let erode = CIFilter.morphologyMinimum()
        erode.inputImage = mask.clampedToExtent()
        erode.radius = radius
        return erode.outputImage?.cropped(to: rect) ?? mask
    }

    private static func multiply(_ a: CIImage, _ b: CIImage) -> CIImage {
        let f = CIFilter.multiplyCompositing()
        f.inputImage = a
        f.backgroundImage = b
        return f.outputImage ?? a
    }

    /// Mean of the red channel over `rect`.
    private static func mean(_ image: CIImage, _ rect: CGRect) -> Double {
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: rect)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16,
                       bounds: CGRect(x: average.extent.minX, y: average.extent.minY, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return Double(pixel[0])
    }

    /// The photo drawn upright at most `side` px on its long side.
    private static func upright(_ image: UIImage) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, side / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
