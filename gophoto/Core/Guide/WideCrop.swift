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
import UIKit
import Vision

nonisolated enum WideCrop {

    /// Never crop to fewer pixels than this (megapixels).
    static let minOutputMegapixels = 6.0
    /// Never stand more than 2x farther than the preset: perspective flattens beyond that.
    static let minScale = 0.5
    /// The person may be at most this much bigger than the target (no crop needed, slight zoom-out).
    static let maxScale = 1.05
    /// Horizon tilts up to this many degrees are rotated away in the crop.
    static let maxRollCorrection = 6.0
    /// Smaller tilts are left alone: rotating resamples every pixel and softens the photo.
    static let minRollCorrection = 1.0
    /// Quality of the saved crop (same format as the camera file, usually HEIC).
    static let outputQuality = 0.95

    /// Smallest allowed person size relative to the target, from the camera resolution.
    static func minimumScale(photoMegapixels: Double?) -> Double {
        let mp = photoMegapixels ?? 12
        return max(minScale, (minOutputMegapixels / mp).squareRoot())
    }

    /// Half body: the preset's body, measured on its photos. A cut-off person box is "head to
    /// frame edge", not the person's size, so the crop uses the torso instead: its length sets
    /// the size and the neck the position. The cut then lands at the same point of the legs for
    /// short and tall people alike (everything scales with the torso).
    nonisolated struct TorsoTarget: Sendable {
        /// Neck position in the preset's photos (normalized, origin top-left).
        var neck: CGPoint
        /// Neck-to-hip length, frame heights.
        var torso: Double
    }

    /// The torso (neck point, neck-to-hip length) of the person in `image`, from Vision's body
    /// pose: the pose whose neck lies inside `person` (normalized, top-left). Nil when not found.
    static func torso(in image: CIImage, person: CGRect) -> (neck: CGPoint, length: Double)? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(ciImage: image, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil, let poses = request.results else { return nil }
        let region = person.insetBy(dx: -person.width * 0.1, dy: -person.height * 0.1)
        var best: (neck: CGPoint, length: Double)?
        for pose in poses {
            func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let p = try? pose.recognizedPoint(joint), p.confidence >= 0.3 else { return nil }
                return CGPoint(x: p.location.x, y: 1 - p.location.y)          // Vision is bottom-left
            }
            guard let neck = point(.neck) else { continue }
            let hips = [point(.leftHip), point(.rightHip)].compactMap { $0 }
            guard let hip = point(.root) ?? (hips.isEmpty ? nil
                    : CGPoint(x: hips.map(\.x).reduce(0, +) / CGFloat(hips.count),
                              y: hips.map(\.y).reduce(0, +) / CGFloat(hips.count))) else { continue }
            let length = Double(hip.y - neck.y)
            guard length > 0.02, region.contains(neck) else { continue }
            if best.map({ length > $0.length }) ?? true { best = (neck, length) }
        }
        return best
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
    static func crop(_ data: Data, person: CGRect, target: CGRect, torsoTarget: TorsoTarget? = nil,
                     rollDegrees: Double, photoMegapixels: Double?) -> Data? {
        guard target.height > 0,
              let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }
        let extent = image.extent
        let w = extent.width, h = extent.height
        let minimum = minimumScale(photoMegapixels: photoMegapixels)

        // Half body: size from the torso, neck onto the preset's neck. Else (full body, or no
        // torso found): the person box, as before.
        let window: CGRect
        if let torsoTarget, torsoTarget.torso > 0, let body = torso(in: image, person: person) {
            let c = CGFloat(min(maxScale, max(minimum, body.length / torsoTarget.torso)))
            window = clamped(CGRect(x: body.neck.x - torsoTarget.neck.x * c, y: body.neck.y - torsoTarget.neck.y * c,
                                    width: c, height: c))
        } else {
            let scale = min(maxScale, max(minimum, Double(person.height / target.height)))
            window = clamped(self.window(person: person, target: target, scale: scale))
        }
        // Normalized top-left → Core Image pixels (origin bottom-left).
        let rect = CGRect(x: extent.minX + window.minX * w,
                          y: extent.minY + (1 - window.maxY) * h,
                          width: window.width * w, height: window.height * h)

        // Straighten: the phone turned clockwise, so turn the picture clockwise back (negative in CI).
        var output = image
        let roll = (minRollCorrection...maxRollCorrection).contains(abs(rollDegrees)) ? rollDegrees : 0
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

        // Written like the camera file (format, metadata, upright), not re-encoded as JPEG.
        let cropped = output.cropped(to: rect)
        guard let cgImage = CIContext().createCGImage(cropped, from: rect.integral) else { return nil }
        return CapturedPhotoEnhancing.file(for: UIImage(cgImage: cgImage), metadataFrom: data, quality: outputQuality)
    }
}
