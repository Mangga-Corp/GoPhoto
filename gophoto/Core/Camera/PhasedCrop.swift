//
//  PhasedCrop.swift
//  gophoto
//
//  Phased · Auto crop: applies the crop shown in the preview to the saved photo (the original is
//  saved too, as the app always does). With an output shape (the camera's 9:16) the result is cut
//  to exactly that shape inside the preview's visible band. Never below the quality floor, never upscaled: when the
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
    ///   - bounds: normalized part of the photo the crop must stay in (the preview's visible band).
    ///   - outputShape: exact pixel proportions of the result (e.g. 9:16). Nil = the original
    ///     behaviour: the crop's own shape, no crop below the floor or for the whole photo. With a
    ///     shape the photo is always cut to it (inside `bounds`), never stretched or upscaled.
    static func apply(imageData: Data, crop: CGRect, rollDegrees: Double, floorMegapixels: Double,
                      bounds: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                      outputShape: (width: Int, height: Int)? = nil) -> Result {
        let context = CIContext()
        guard let image = CIImage(data: imageData, options: [.applyOrientationProperty: true]) else {
            return Result(data: nil, note: "could not read the photo", sourceSize: .zero, rollDegrees: 0)
        }
        let extent = image.extent
        let w = extent.width, h = extent.height
        let source = CGSize(width: w, height: h)
        let floorPixels = floorMegapixels * 1_000_000
        guard outputShape != nil || Double(w * h) > floorPixels else {
            return Result(data: nil, note: String(format: "photo %.1f MP is not above the %.0f MP floor: not cropped",
                                                  Double(w * h) / 1e6, floorMegapixels),
                          sourceSize: source, rollDegrees: 0)
        }
        // Normalized top-left → Core Image pixels (origin bottom-left).
        func pixels(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h)
        }
        let area = pixels(bounds).intersection(extent)
        guard !area.isNull, area.width >= 1, area.height >= 1 else {
            return Result(data: nil, note: "empty crop bounds", sourceSize: source, rollDegrees: 0)
        }
        var rect = pixels(crop)
        var note = ""
        if let shape = outputShape {
            rect = Self.reshaped(rect, ratio: CGFloat(shape.width) / CGFloat(shape.height), in: area)
        }
        if Double(rect.width * rect.height) < floorPixels {
            let s = CGFloat(sqrt(floorPixels / Double(rect.width * rect.height)))
            var grown = rect.insetBy(dx: -rect.width * (s - 1) / 2, dy: -rect.height * (s - 1) / 2)
            // Never past the allowed area: shrink back evenly, so the shape stays.
            let fit = min(1, area.width / grown.width, area.height / grown.height)
            if fit < 1 {
                grown = CGRect(x: grown.midX - grown.width * fit / 2, y: grown.midY - grown.height * fit / 2,
                               width: grown.width * fit, height: grown.height * fit)
            }
            rect = CGRect(x: min(max(grown.minX, area.minX), area.maxX - grown.width),
                          y: min(max(grown.minY, area.minY), area.maxY - grown.height),
                          width: grown.width, height: grown.height)
            note += "enlarged to the floor · "
        }
        if let shape = outputShape {
            rect = Self.exact(rect, shape: shape, in: area)
            guard rect.width >= 1, rect.height >= 1 else {
                return Result(data: nil, note: "crop too small for the shape", sourceSize: source, rollDegrees: 0)
            }
        } else {
            rect = rect.integral.intersection(extent)
            if rect.width >= w - 1, rect.height >= h - 1, abs(rollDegrees) < 0.5 {
                return Result(data: nil, note: "crop = whole photo: not cropped", sourceSize: source, rollDegrees: 0)
            }
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

    /// `rect` with width / height = `ratio` (same height and centre where it fits), inside `area`.
    private static func reshaped(_ rect: CGRect, ratio: CGFloat, in area: CGRect) -> CGRect {
        var height = rect.height
        var width = height * ratio
        if width > area.width { width = area.width; height = width / ratio }
        if height > area.height { height = area.height; width = height * ratio }
        let x = min(max(rect.midX - width / 2, area.minX), area.maxX - width)
        let y = min(max(rect.midY - height / 2, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Whole pixels in exactly `shape`'s proportions (e.g. 9:16 → 1512×2688), at most `rect`'s
    /// size, centred on it and inside `area`.
    private static func exact(_ rect: CGRect, shape: (width: Int, height: Int), in area: CGRect) -> CGRect {
        let inner = CGRect(x: area.minX.rounded(.up), y: area.minY.rounded(.up),
                           width: (area.maxX.rounded(.down) - area.minX.rounded(.up)),
                           height: (area.maxY.rounded(.down) - area.minY.rounded(.up)))
        let unitsByHeight = Int(min(rect.height, inner.height)) / shape.height
        let unitsByWidth = Int(min(rect.width, inner.width)) / shape.width
        let units = max(0, min(unitsByHeight, unitsByWidth))
        let width = CGFloat(units * shape.width), height = CGFloat(units * shape.height)
        let x = min(max((rect.midX - width / 2).rounded(), inner.minX), inner.maxX - width)
        let y = min(max((rect.midY - height / 2).rounded(), inner.minY), inner.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
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
