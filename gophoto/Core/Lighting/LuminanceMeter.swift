//
//  LuminanceMeter.swift
//  gophoto
//
//  Core layer: measures how bright the face and the whole frame are from a camera pixel buffer.
//  Runs on the video queue; the frame is shrunk first so a reading stays cheap.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo

nonisolated final class LuminanceMeter {

    /// Brightness readings, 0 (black) ... 1 (white), as encoded in the frame.
    struct Reading: Sendable, Equatable {
        let face: Double?
        let frame: Double
        /// The background left and right of the person; nil when that side is too narrow to judge.
        let left: Double?
        let right: Double?
    }

    /// Width of the shrunk copy that is averaged.
    private static let sampleWidth: CGFloat = 96
    /// A side narrower than this share of the frame says too little about where the light comes from.
    private static let minSideWidth: CGFloat = 0.1

    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// - Parameters:
    ///   - face: the face box, normalized, origin TOP-LEFT, upright frame.
    ///   - person: the person's box, same space; the background beside it is measured too.
    func measure(_ pixelBuffer: CVPixelBuffer, face: CGRect?, person: CGRect?) -> Reading? {
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard image.extent.width > 0 else { return nil }

        let shrink = CIFilter.lanczosScaleTransform()
        shrink.inputImage = image
        shrink.scale = Float(Self.sampleWidth / image.extent.width)
        shrink.aspectRatio = 1
        guard let small = shrink.outputImage, let frame = average(of: small) else { return nil }

        var faceLuminance: Double?
        if let face {
            let box = CGRect(x: face.minX * small.extent.width,
                             y: (1 - face.maxY) * small.extent.height,
                             width: face.width * small.extent.width,
                             height: face.height * small.extent.height)
                .intersection(small.extent)
            if box.width >= 1, box.height >= 1 {
                faceLuminance = average(of: small.cropped(to: box))
            }
        }
        let width = small.extent.width, height = small.extent.height
        func side(from minX: CGFloat, to maxX: CGFloat) -> Double? {
            guard maxX - minX >= Self.minSideWidth else { return nil }
            return average(of: small.cropped(to: CGRect(x: minX * width, y: 0, width: (maxX - minX) * width, height: height)))
        }
        let left = person.flatMap { side(from: 0, to: max(0, $0.minX)) }
        let right = person.flatMap { side(from: min(1, $0.maxX), to: 1) }
        return Reading(face: faceLuminance, frame: frame, left: left, right: right)
    }

    private func average(of image: CIImage) -> Double? {
        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = image.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }
}
