//
//  PhasedCrop.swift
//  gophoto
//
//  Phased · Auto crop: applies the crop shown in the preview to the saved photo (the original is
//  saved too, as the app always does). Never below the quality floor, never upscaled: when the
//  wanted crop is too small it is enlarged to the floor (person a little smaller than the
//  reference), and when the photo itself is below the floor nothing is cropped. Each result says
//  what was done (logged per shutter).
//
import CoreImage
import Foundation
import ImageIO

nonisolated enum PhasedCrop {

    struct Result: Sendable {
        /// The cropped file (HEIC), nil when no crop was made.
        var data: Data?
        var note: String
        /// Upright photo size and the saved crop size, pixels.
        var sourceSize: CGSize
        var outputSize: CGSize?
        /// The crop actually applied (normalized, origin top-left) and its rotation, degrees.
        var applied: CGRect?
        var rollDegrees: Double
    }

    /// - Parameters:
    ///   - crop: normalized, origin top-left, of the upright photo (same aspect as the photo).
    ///   - rollDegrees: rotate the image this much (counter-clockwise +) about the crop centre first.
    static func apply(imageData: Data, crop: CGRect, rollDegrees: Double, floorMegapixels: Double) -> Result {
        let context = CIContext()
        guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else {
            return Result(data: nil, note: "could not read the photo", sourceSize: .zero, rollDegrees: 0)
        }
        let extent = image.extent
        let w = extent.width, h = extent.height
        let source = CGSize(width: w, height: h)
        let floorPixels = floorMegapixels * 1_000_000
        guard Double(w * h) > floorPixels else {
            return Result(data: nil, note: String(format: "photo %.1f MP is not above the %.0f MP floor: not cropped",
                                                  Double(w * h) / 1e6, floorMegapixels),
                          sourceSize: source, rollDegrees: 0)
        }
        // Normalized top-left → Core Image pixels (origin bottom-left).
        var rect = CGRect(x: crop.minX * w, y: (1 - crop.maxY) * h, width: crop.width * w, height: crop.height * h)
        var note = ""
        if Double(rect.width * rect.height) < floorPixels {
            let s = sqrt(floorPixels / Double(rect.width * rect.height))
            let grown = rect.insetBy(dx: -rect.width * CGFloat(s - 1) / 2, dy: -rect.height * CGFloat(s - 1) / 2)
            rect = CGRect(x: min(max(grown.minX, 0), w - grown.width), y: min(max(grown.minY, 0), h - grown.height),
                          width: min(grown.width, w), height: min(grown.height, h))
            note += "enlarged to the floor · "
        }
        rect = rect.integral.intersection(extent)
        if rect.width >= w - 1, rect.height >= h - 1, abs(rollDegrees) < 0.5 {
            return Result(data: nil, note: "crop = whole photo: not cropped", sourceSize: source, rollDegrees: 0)
        }

        var working = image
        var roll = 0.0
        if abs(rollDegrees) >= 0.5 {
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let t = CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: CGFloat(rollDegrees * .pi / 180))
                .translatedBy(x: -c.x, y: -c.y)
            let rotated = image.transformed(by: t)
            // Only when the crop still lies on real pixels after the rotation.
            if rotated.extent.contains(rect), Self.cornersInside(rect, rotation: rollDegrees, extent: extent) {
                working = rotated
                roll = rollDegrees
            } else {
                note += "roll skipped (crop would leave the photo) · "
            }
        }
        let output = working.cropped(to: rect).transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        var properties = image.properties
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImagePropertyPixelWidth as String] = nil
        properties[kCGImagePropertyPixelHeight as String] = nil
        let tagged = output.settingProperties(properties)
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let data = context.heifRepresentation(of: tagged, format: .RGBA8, colorSpace: colorSpace,
                                              options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92])
            ?? context.jpegRepresentation(of: tagged, colorSpace: colorSpace, options: [:])
        let normalized = CGRect(x: rect.minX / w, y: 1 - rect.maxY / h, width: rect.width / w, height: rect.height / h)
        note += String(format: "crop %.0f×%.0f (%.1f MP)", rect.width, rect.height, Double(rect.width * rect.height) / 1e6)
        return Result(data: data, note: note, sourceSize: source, outputSize: rect.size, applied: normalized,
                      rollDegrees: roll)
    }

    /// The crop's corners, mapped back into the unrotated photo, stay inside it.
    private static func cornersInside(_ rect: CGRect, rotation degrees: Double, extent: CGRect) -> Bool {
        let a = -degrees * .pi / 180
        let c = CGPoint(x: rect.midX, y: rect.midY)
        for p in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                  CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)] {
            let dx = Double(p.x - c.x), dy = Double(p.y - c.y)
            let x = Double(c.x) + dx * cos(a) - dy * sin(a)
            let y = Double(c.y) + dx * sin(a) + dy * cos(a)
            if !extent.insetBy(dx: -0.5, dy: -0.5).contains(CGPoint(x: x, y: y)) { return false }
        }
        return true
    }
}
