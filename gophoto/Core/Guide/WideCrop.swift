//
//  WideCrop.swift
//  gophoto
//
//  Mode F: shoot a little wider than the preset, then crop so the person's size and
//  position match the preset, and rotate small horizon tilts away. Only camera height
//  and tilt are guided live, because a crop cannot change perspective.
//
import CoreGraphics
import CoreImage
import Foundation
import ImageIO

nonisolated enum WideCrop {

    /// Never crop to fewer pixels than this (megapixels).
    static let minOutputMegapixels = 6.0
    /// Never stand more than 2x farther than the preset: perspective flattens beyond that.
    static let minScale = 0.5
    /// The person may be at most this much bigger than the target (no crop needed, slight zoom-out).
    static let maxScale = 1.05
    /// Horizon tilts up to this many degrees are rotated away in the crop.
    static let maxRollCorrection = 6.0

    /// Smallest allowed person size relative to the target, from the camera resolution.
    static func minimumScale(photoMegapixels: Double?) -> Double {
        let mp = photoMegapixels ?? 12
        return max(minScale, (minOutputMegapixels / mp).squareRoot())
    }

    /// The crop (normalized, origin top-left, same aspect as the frame) that puts `person`
    /// where `target` is. `scale` = person height / target height. Not clamped.
    static func window(person: CGRect, target: CGRect, scale: Double) -> CGRect {
        let c = CGFloat(scale)
        return CGRect(x: person.midX - target.midX * c, y: person.midY - target.midY * c, width: c, height: c)
    }

    /// The window moved inside the frame (the person may end up off the target position).
    static func clamped(_ w: CGRect) -> CGRect {
        let c = min(1, max(w.width, 0.01))
        return CGRect(x: min(max(0, w.minX), 1 - c), y: min(max(0, w.minY), 1 - c), width: c, height: c)
    }

    // MARK: Crop a captured photo

    /// Crops (and straightens) a captured photo. Returns JPEG data, or nil when it cannot.
    /// - Parameters:
    ///   - person, target: normalized boxes, origin top-left, upright frame.
    ///   - rollDegrees: phone roll at the shutter (+ = rotated clockwise).
    static func crop(_ data: Data, person: CGRect, target: CGRect,
                     rollDegrees: Double, photoMegapixels: Double?) -> Data? {
        guard target.height > 0,
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let extent = image.extent
        let w = extent.width, h = extent.height

        let scale = min(maxScale, max(minimumScale(photoMegapixels: photoMegapixels),
                                      Double(person.height / target.height)))
        let window = clamped(self.window(person: person, target: target, scale: scale))
        // Normalized top-left → Core Image pixels (origin bottom-left).
        let rect = CGRect(x: extent.minX + window.minX * w,
                          y: extent.minY + (1 - window.maxY) * h,
                          width: window.width * w, height: window.height * h)

        // Straighten: the phone turned clockwise, so turn the picture clockwise back (negative in CI).
        var output = image
        let roll = abs(rollDegrees) <= maxRollCorrection ? rollDegrees : 0
        if roll != 0 {
            let angle = CGFloat(-roll * .pi / 180)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let turn = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: angle)
                .translatedBy(x: -center.x, y: -center.y)
            let rotated = image.transformed(by: turn)
            // Only keep the rotation if the crop stays inside the rotated picture (no empty corners).
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
            let back = turn.inverted()
            if corners.allSatisfy({ extent.insetBy(dx: -0.5, dy: -0.5).contains($0.applying(back)) }) {
                output = rotated
            }
        }

        let cropped = output.cropped(to: rect)
        let context = CIContext()
        let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        return context.jpegRepresentation(
            of: cropped, colorSpace: colorSpace,
            options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.92])
    }
}
