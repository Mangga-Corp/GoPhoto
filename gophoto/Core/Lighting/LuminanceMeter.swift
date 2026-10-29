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
        /// The face; the head (top of the person's box) when no face is found, which is what a
        /// silhouette gives; nil without a person.
        let face: Double?
        let frame: Double
        /// The brightest area behind and around the person (a window, the sky, a lamp). It tells a
        /// backlit person in a dark room from a room that is simply dark, which the frame average
        /// cannot: dark walls pull that average down.
        let peak: Double
        /// The background left and right of the person; nil when that side is too narrow to judge.
        let left: Double?
        let right: Double?
    }

    /// Width of the shrunk copy that is averaged.
    private static let sampleWidth: CGFloat = 96
    /// A side narrower than this share of the frame says too little about where the light comes from.
    private static let minSideWidth: CGFloat = 0.1
    /// The peak is the brightest cell of a coarse grid this many cells wide, so one small lamp
    /// averages out and only a window-sized light counts.
    private static let gridColumns = 8
    /// The head is the top of the person's box: this share of its height, and the middle share of
    /// its width (the box is wider than the head, and the light behind would leak in at the sides).
    private static let headHeightShare: CGFloat = 0.16
    private static let headWidthShare: CGFloat = 0.4
    /// The peak looks this far (share of the person's width) beyond each side of the person.
    private static let peakReach: CGFloat = 0.5

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
        let head = person.map {
            CGRect(x: $0.midX - $0.width * Self.headWidthShare / 2, y: $0.minY,
                   width: $0.width * Self.headWidthShare, height: $0.height * Self.headHeightShare)
        }
        if let region = face ?? head {
            let box = CGRect(x: region.minX * small.extent.width,
                             y: (1 - region.maxY) * small.extent.height,
                             width: region.width * small.extent.width,
                             height: region.height * small.extent.height)
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
        let peak = peakLuminance(of: small, around: person) ?? frame
        return Reading(face: faceLuminance, frame: frame, peak: peak, left: left, right: right)
    }

    /// The brightest cell of a coarse grid over the frame, limited to the columns at and beside
    /// the person (the whole frame when nobody is found). One render for the whole grid.
    private func peakLuminance(of image: CIImage, around person: CGRect?) -> Double? {
        let columns = Self.gridColumns
        let shrink = CIFilter.lanczosScaleTransform()
        shrink.inputImage = image
        shrink.scale = Float(CGFloat(columns) / image.extent.width)
        shrink.aspectRatio = 1
        guard let grid = shrink.outputImage else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: columns, height: Int(grid.extent.height.rounded()))
        guard bounds.height >= 1 else { return nil }
        let rowBytes = columns * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * Int(bounds.height))
        context.render(grid, toBitmap: &pixels, rowBytes: rowBytes, bounds: bounds, format: .RGBA8, colorSpace: nil)

        var firstColumn = 0, lastColumn = columns - 1
        if let person {
            let reach = person.width * Self.peakReach
            firstColumn = max(0, Int(((person.minX - reach) * CGFloat(columns)).rounded(.down)))
            lastColumn = min(columns - 1, Int(((person.maxX + reach) * CGFloat(columns)).rounded(.up)) - 1)
        }
        guard firstColumn <= lastColumn else { return nil }
        var peak = 0.0
        for row in 0..<Int(bounds.height) {
            for column in firstColumn...lastColumn {
                let i = row * rowBytes + column * 4
                let value = (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
                peak = max(peak, value)
            }
        }
        return peak
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
