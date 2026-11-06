//
//  BokehProcessor.swift
//  gophoto
//
//  Background blur copy after capture (developer mode 2 only, for now), matched to the preset's
//  references (version 18): the references' background / person sharpness ratio
//  (`BackgroundBlurMeter`) is the target, and the blur strength is searched until the copy has
//  the same ratio. Apple's depth blur (`CIDepthBlurEffect`) when the photo carries depth, else a
//  Gaussian blur behind a segmentation mask. The subject (person + what they hold) is always put
//  back sharp on top, and Apple's blur is focused on the largest face.
//
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

nonisolated enum BokehProcessor {

    /// Strongest custom blur radius, as a fraction of the photo's short side.
    static let maxRadiusFraction: CGFloat = 0.01
    /// The person's mask is grown by this much (fraction of the short side) for the custom blur.
    static let growFraction: CGFloat = 0.003
    /// Softening of the subject's edge, fraction of the short side.
    static let featherFraction: CGFloat = 0.0015
    /// References at or above this ratio have a sharp background: no blur copy.
    static let sharpReferenceRatio = 0.85
    /// Without a reference target: this share of the way from the weakest to the strongest blur.
    static let fallbackAmount = 1.0 / 3.0
    /// Search steps (each renders the blur once).
    static let searchSteps = 6

    private static let context = CIContext()

    /// The blur copy as HEIC (else JPEG) data, and a note for the debug panel. `data` is nil when
    /// no copy should be made (sharp references, no person, already as blurred as the target).
    /// Slow (several renders): call it off the main actor.
    static func blurToTarget(imageData: Data, target: Double?) -> (data: Data?, note: String) {
        let upright: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let image = CIImage(data: imageData, options: upright) else { return (nil, "blur: unreadable photo") }
        let extent = image.extent
        let shortSide = min(extent.width, extent.height)
        if let target, target >= sharpReferenceRatio {
            return (nil, String(format: "blur: references sharp (%.2f) → no copy", target))
        }

        // Subject and face.
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest()
        let subjectRequest = VNGenerateForegroundInstanceMaskRequest()
        let personRequest = VNGeneratePersonSegmentationRequest()
        personRequest.qualityLevel = .accurate
        personRequest.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? handler.perform([faceRequest, subjectRequest, personRequest])

        // Depth (Apple path), upright like the photo.
        var rawDisparity = CIImage(data: imageData, options: upright.merging([.auxiliaryDisparity: true]) { $1 })
        if rawDisparity == nil, let depth = CIImage(data: imageData, options: upright.merging([.auxiliaryDepth: true]) { $1 }) {
            rawDisparity = depth.applyingFilter("CIDepthToDisparity")
        }
        let tag = (CIImage(data: imageData)?.properties[kCGImagePropertyOrientation as String] as? NSNumber)
            .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        func matchPhoto(_ aux: CIImage) -> CIImage {
            (aux.extent.width > aux.extent.height) == (extent.width > extent.height) ? aux : aux.oriented(tag)
        }
        let matte = CIImage(data: imageData, options: upright.merging([.auxiliaryPortraitEffectsMatte: true]) { $1 })
            .map(matchPhoto)

        // Subject mask (1 = keep sharp): foreground subject, else Apple's matte, else the person.
        var note = ""
        var subject: CIImage?
        if let observation = subjectRequest.results?.first,
           let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) {
            subject = CIImage(cvPixelBuffer: buffer); note += "keep subject"
        } else if let matte {
            subject = matte; note += "keep matte"
        } else if let buffer = personRequest.results?.first?.pixelBuffer {
            subject = CIImage(cvPixelBuffer: buffer); note += "keep person"
        }
        guard let subjectMask = subject.map({ BackgroundBlurMeter.fit($0, to: extent) }) else {
            return (nil, "blur: no person")
        }
        let grow = CIFilter.morphologyMaximum()
        grow.inputImage = subjectMask.clampedToExtent()
        grow.radius = Float(shortSide * growFraction)
        let keepMask = (grow.outputImage ?? subjectMask.clampedToExtent())
            .applyingGaussianBlur(sigma: Double(shortSide * featherFraction))
            .cropped(to: extent)
        func keepSubject(_ blurred: CIImage) -> CIImage {
            let blend = CIFilter.blendWithMask()
            blend.inputImage = image
            blend.backgroundImage = blurred
            blend.maskImage = keepMask
            return blend.outputImage?.cropped(to: extent) ?? blurred
        }

        // Renderer: amount 0 = weakest, 1 = strongest blur.
        let render: (Double) -> CIImage
        if let disparity = rawDisparity.map(matchPhoto),
           let filter = context.depthBlurEffectFilter(for: image, disparityImage: disparity,
                                                      portraitEffectsMatte: matte, orientation: .up, options: nil) {
            if let face = faceRequest.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height }) {
                filter.setValue(CIVector(cgRect: face.boundingBox), forKey: "inputFocusRect")   // normalised
                note += " · focus face"
            }
            let attributes = filter.attributes["inputAperture"] as? [String: Any]
            let low = (attributes?[kCIAttributeSliderMin] as? NSNumber)?.doubleValue ?? 0
            let high = (attributes?[kCIAttributeSliderMax] as? NSNumber)?.doubleValue
                ?? ((attributes?[kCIAttributeDefault] as? NSNumber)?.doubleValue ?? 4) * 2
            func apple(_ aperture: Double) -> CIImage {
                filter.setValue(aperture, forKey: "inputAperture")
                return keepSubject(filter.outputImage?.cropped(to: extent) ?? image)
            }
            // Which end blurs more is measured, not assumed.
            let rLow = BackgroundBlurMeter.ratio(image: apple(low), personMask: subjectMask) ?? 1
            let rHigh = BackgroundBlurMeter.ratio(image: apple(high), personMask: subjectMask) ?? 1
            let (weak, strong) = rLow >= rHigh ? (low, high) : (high, low)
            note = String(format: "apple depth · aperture %.1f→%.1f · ", weak, strong) + note
            render = { amount in apple(weak + (strong - weak) * amount) }
        } else {
            note = "custom · " + note
            render = { amount in
                let radius = Double(shortSide * maxRadiusFraction) * amount
                let blurred = radius > 0.5 ? image.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: extent) : image
                return keepSubject(blurred)
            }
        }
        func ratio(_ amount: Double) -> Double {
            BackgroundBlurMeter.ratio(image: render(amount), personMask: subjectMask) ?? 1
        }

        // Amount: match the references' ratio, else the fallback share.
        var amount = fallbackAmount
        if let target {
            let sharpest = ratio(0)
            if sharpest <= target {
                return (nil, note + String(format: " · already %.2f ≤ target %.2f → no copy", sharpest, target))
            }
            var lo = 0.0, hi = 1.0
            for _ in 0..<searchSteps {
                let mid = (lo + hi) / 2
                if ratio(mid) > target { lo = mid } else { hi = mid }
            }
            amount = hi
            note += String(format: " · target %.2f got %.2f @ %.2f", target, ratio(amount), amount)
        } else {
            note += String(format: " · no reference target → %.2f", amount)
        }

        let output = render(amount)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let data = context.heifRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace, options: [:])
            ?? context.jpegRepresentation(of: output, colorSpace: colorSpace, options: [:])
        return (data, note)
    }
}
