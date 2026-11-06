//
//  BokehProcessor.swift
//  gophoto
//
//  Background blur after capture (developer mode 2 only, for now).
//  Vision person segmentation → the background is blurred with CIMaskedVariableBlur at
//  `strength` (0...1) of the strongest blur. The person stays sharp; the mask edge is feathered.
//  Works on every iPhone the app supports (no depth camera needed), and touches nothing in the
//  live camera, zoom or guide: it only runs on the finished photo.
//
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

nonisolated enum BokehProcessor {

    /// Strongest blur radius, as a fraction of the photo's short side. v1 used 3%: half of it
    /// (45 px on a 12 MP photo) smeared everything and ate the person's edges. 1% → half = 15 px.
    static let maxRadiusFraction: CGFloat = 0.01
    /// Strength used by the app: half of the strongest blur.
    static let defaultStrength: CGFloat = 0.5
    /// The person's mask is grown by this much first (fraction of the short side), so the blur
    /// never reaches into arms, hair or legs where the segmentation is a little short.
    static let growFraction: CGFloat = 0.003
    /// Softening of the person's edge, as a fraction of the short side (hides a hard cut-out line).
    /// Small: a wide feather blurred the person's own edges.
    static let featherFraction: CGFloat = 0.0015

    private static let context = CIContext()

    /// Apple's portrait blur (`CIDepthBlurEffect` via `depthBlurEffectFilter`), from the depth and
    /// portrait matte the camera embedded in the photo. Apple's default aperture; the note says
    /// which values it had (for tuning). Nil when the photo has no depth (use `blurBackground`).
    static func appleDepthBlur(imageData: Data) -> (data: Data, note: String)? {
        // Everything upright BEFORE the filter (photo, disparity, matte all with the orientation
        // tag applied, filter told ".up"): the output is then upright by construction. Letting the
        // filter read the file itself gave a copy turned 90° (twice, in two different fixes).
        let upright: [CIImageOption: Any] = [.applyOrientationProperty: true]
        guard let image = CIImage(data: imageData, options: upright) else { return nil }
        var rawDisparity = CIImage(data: imageData, options: upright.merging([.auxiliaryDisparity: true]) { $1 })
        if rawDisparity == nil, let depth = CIImage(data: imageData, options: upright.merging([.auxiliaryDepth: true]) { $1 }) {
            rawDisparity = depth.applyingFilter("CIDepthToDisparity")
        }
        // In case an auxiliary image ignores the orientation option: same shape as the photo.
        let tag = (CIImage(data: imageData)?.properties[kCGImagePropertyOrientation as String] as? NSNumber)
            .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
        func matchPhoto(_ aux: CIImage) -> CIImage {
            (aux.extent.width > aux.extent.height) == (image.extent.width > image.extent.height) ? aux : aux.oriented(tag)
        }
        guard let disparity = rawDisparity.map(matchPhoto) else { return nil }
        let matte = CIImage(data: imageData, options: upright.merging([.auxiliaryPortraitEffectsMatte: true]) { $1 })
            .map(matchPhoto)
        guard let filter = context.depthBlurEffectFilter(for: image, disparityImage: disparity,
                                                         portraitEffectsMatte: matte, orientation: .up,
                                                         options: nil) else { return nil }
        var note = "apple depth"
        if let aperture = filter.attributes["inputAperture"] as? [String: Any] {
            func value(_ key: String) -> String { (aperture[key] as? NSNumber).map { String(format: "%.1f", $0.doubleValue) } ?? "?" }
            let now = (filter.value(forKey: "inputAperture") as? NSNumber).map { String(format: "%.1f", $0.doubleValue) } ?? "?"
            note += " · aperture \(now) (min \(value(kCIAttributeSliderMin)), max \(value(kCIAttributeSliderMax)), default \(value(kCIAttributeDefault)))"
        }
        // Subject: the largest face sets the focus (the filter focused on a hand held closer to
        // the camera), and the subject mask keeps the whole person sharp whatever the focus is.
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let faceRequest = VNDetectFaceRectanglesRequest()
        let subjectRequest = VNGenerateForegroundInstanceMaskRequest()
        try? handler.perform([faceRequest, subjectRequest])
        if let face = faceRequest.results?.max(by: { $0.boundingBox.height < $1.boundingBox.height }) {
            // Normalised, bottom-left origin (Vision and Core Image agree).
            filter.setValue(CIVector(cgRect: face.boundingBox), forKey: "inputFocusRect")
            note += " · focus face"
        } else {
            note += " · focus auto (no face)"
        }
        guard let blurred = filter.outputImage?.cropped(to: image.extent) else { return nil }

        // Subject mask: Vision's foreground subject (person + what they hold), else Apple's
        // portrait matte (person only). Scaled to the photo, edge softened a little.
        let extent = image.extent
        let shortSide = min(extent.width, extent.height)
        var subject: CIImage?
        if let observation = subjectRequest.results?.first,
           let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) {
            subject = CIImage(cvPixelBuffer: buffer)
            note += " · keep subject"
        } else if let matte {
            subject = matte
            note += " · keep matte"
        }
        var output = blurred
        if let mask = subject {
            let scaled = mask
                .transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                   y: extent.height / mask.extent.height))
                .transformed(by: CGAffineTransform(translationX: extent.minX - mask.extent.minX * extent.width / mask.extent.width,
                                                   y: extent.minY - mask.extent.minY * extent.height / mask.extent.height))
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(shortSide * featherFraction))
                .cropped(to: extent)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = image
            blend.backgroundImage = blurred
            blend.maskImage = scaled
            output = blend.outputImage?.cropped(to: extent) ?? blurred
        }
        // Debug: sizes, so a wrong turn shows in the panel.
        note += String(format: " · photo %.0f×%.0f out %.0f×%.0f%@", image.extent.width, image.extent.height,
                       output.extent.width, output.extent.height, matte == nil ? " · no matte" : "")
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let data = context.heifRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace, options: [:])
                ?? context.jpegRepresentation(of: output, colorSpace: colorSpace, options: [:]) else { return nil }
        return (data, note)
    }

    /// The photo with its background blurred, as HEIC (else JPEG) data. Nil when the photo could
    /// not be read or no person was found (then keep only the original).
    /// Slow on a 12 MP photo (segmentation + a large blur): call it off the main actor.
    static func blurBackground(imageData: Data, strength: CGFloat = defaultStrength) -> Data? {
        guard strength > 0,
              let source = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else { return nil }
        let extent = source.extent
        let shortSide = min(extent.width, extent.height)
        guard shortSide > 0 else { return nil }

        // 1. Where the person is (1 = person, 0 = background).
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            try VNImageRequestHandler(ciImage: source, options: [:]).perform([request])
        } catch {
            return nil
        }
        guard let maskBuffer = request.results?.first?.pixelBuffer else { return nil }

        // 2. Person mask at the photo's size, grown a little, edge feathered (1 = person).
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                      y: extent.height / mask.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
        let grow = CIFilter.morphologyMaximum()
        grow.inputImage = mask.clampedToExtent()
        grow.radius = Float(shortSide * growFraction)
        guard let grown = grow.outputImage else { return nil }
        mask = grown
            .applyingGaussianBlur(sigma: Double(shortSide * featherFraction))
            .cropped(to: extent)

        // 3. Blur the whole photo once, then put the ORIGINAL person back on top through the
        //    mask: the person's pixels are never blurred (v1 blurred through a soft mask and the
        //    person's edges went soft too).
        let radius = Double(shortSide * maxRadiusFraction * min(max(strength, 0), 1))
        let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: extent)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = source
        blend.backgroundImage = blurred
        blend.maskImage = mask
        guard let output = blend.outputImage?.cropped(to: extent) else { return nil }

        // 4. Encode. Orientation is already applied to the pixels.
        let colorSpace = source.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.heifRepresentation(of: output, format: .RGBA8, colorSpace: colorSpace, options: [:])
            ?? context.jpegRepresentation(of: output, colorSpace: colorSpace, options: [:])
    }
}
