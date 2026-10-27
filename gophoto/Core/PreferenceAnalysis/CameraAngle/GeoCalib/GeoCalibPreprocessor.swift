// Derived from GeoCalib (https://github.com/cvg/GeoCalib), geocalib/utils.py ImagePreprocessor (+ kornia resize).
// Copyright 2024 ETH Zurich. Licensed under the Apache License, Version 2.0
// (see ThirdPartyNotices/GeoCalib/LICENSE). MODIFIED: ported from Python/PyTorch to Swift,
// pinhole camera and single image only, by the GoPhoto team, October 2026.

import CoreGraphics
import Foundation
import ImageIO

// GeoCalib image preprocessing, identical to geocalib.utils.ImagePreprocessor
// ({"resize": 320, "edge_divisible_by": 32}):
//   1. resize so the SHORT side is 320 (kornia antialias: Gaussian blur, then bilinear, align_corners=False),
//   2. centre-crop each side to a multiple of 32.
// Blur + bilinear are both separable and linear, so each axis is one sparse weight matrix
// (blueprint: preprocess_np.py, matches kornia to 2e-5).
//
// Pixels are taken as stored in the file (no colour management), like OpenCV in the Python code.

nonisolated struct GeoCalibInput: @unchecked Sendable {
    /// 3 x height x width, RGB in [0, 1], planar.
    let pixels: [Float]
    let width: Int
    let height: Int
    let scaleX: Double
    let scaleY: Double
    let cropPadX: Double
    let cropPadY: Double
    let originalWidth: Int
    let originalHeight: Int
}

nonisolated enum GeoCalibPreprocessor {
    static let shortSide = 320
    static let multiple = 32
    /// Long sides the Core ML model accepts (EnumeratedShapes in export_coreml.py).
    static let supportedLongSides = [320, 384, 416, 480, 544]

    enum Failure: Error { case unreadableImage, unsupportedPixelFormat }

    /// Image file data (JPEG / PNG / HEIC). EXIF orientation is applied.
    static func prepare(imageData: Data) throws -> GeoCalibInput {
        guard let cg = uprightImage(from: imageData) else { throw Failure.unreadableImage }
        return try prepare(cgImage: cg)
    }

    /// An image that is already upright.
    static func prepare(cgImage: CGImage) throws -> GeoCalibInput {
        let (rgba, w0, h0) = try rgbaBytes(cgImage)

        // 1. resized size (Python int() truncation)
        let aspect = Double(w0) / Double(h0)
        let rh: Int, rw: Int
        if aspect >= 1 { rh = shortSide; rw = Int(Double(shortSide) * aspect) }
        else { rh = Int(Double(shortSide) / aspect); rw = shortSide }

        // 2. crop to a multiple of 32 (then to a size the model supports)
        var cw = (rw / multiple) * multiple
        var ch = (rh / multiple) * multiple
        if cw > ch { cw = supportedLongSides.last(where: { $0 <= cw }) ?? cw }
        else if ch > cw { ch = supportedLongSides.last(where: { $0 <= ch }) ?? ch }
        let padW = cw - rw, padH = ch - rh                    // <= 0
        let left = -floorDiv(padW, 2), top = -floorDiv(padH, 2)
        let antialias = max(Double(h0) / Double(rh), Double(w0) / Double(rw)) > 1

        let rx = axisWeights(nIn: w0, nOut: rw, outStart: left, outCount: cw, antialias: antialias)
        let ry = axisWeights(nIn: h0, nOut: rh, outStart: top, outCount: ch, antialias: antialias)

        // Horizontal pass: h0 rows x cw columns x 3 (reads RGBA bytes directly).
        var tmp = [Float](repeating: 0, count: h0 * cw * 3)
        rgba.withUnsafeBufferPointer { src in
            tmp.withUnsafeMutableBufferPointer { dst in
                for y in 0..<h0 {
                    let rowIn = y * w0 * 4
                    let rowOut = y * cw * 3
                    for (ox, taps) in rx.enumerated() {
                        var r: Float = 0, g: Float = 0, b: Float = 0
                        for t in 0..<taps.indices.count {
                            let w = taps.weights[t]
                            let p = rowIn + taps.indices[t] * 4
                            r += w * Float(src[p]); g += w * Float(src[p + 1]); b += w * Float(src[p + 2])
                        }
                        let o = rowOut + ox * 3
                        dst[o] = r; dst[o + 1] = g; dst[o + 2] = b
                    }
                }
            }
        }

        // Vertical pass -> planar 3 x ch x cw, scaled to [0, 1].
        var out = [Float](repeating: 0, count: 3 * ch * cw)
        let plane = ch * cw
        tmp.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for (oy, taps) in ry.enumerated() {
                    for x in 0..<cw {
                        var r: Float = 0, g: Float = 0, b: Float = 0
                        for t in 0..<taps.indices.count {
                            let w = taps.weights[t]
                            let p = (taps.indices[t] * cw + x) * 3
                            r += w * src[p]; g += w * src[p + 1]; b += w * src[p + 2]
                        }
                        let o = oy * cw + x
                        dst[o] = r / 255; dst[plane + o] = g / 255; dst[2 * plane + o] = b / 255
                    }
                }
            }
        }

        return GeoCalibInput(pixels: out, width: cw, height: ch,
                             scaleX: Double(rw) / Double(w0), scaleY: Double(rh) / Double(h0),
                             cropPadX: Double(padW), cropPadY: Double(padH),
                             originalWidth: w0, originalHeight: h0)
    }

    // MARK: - Separable resize weights

    struct Taps {
        var indices: [Int]
        var weights: [Float]
    }

    /// Rows of (bilinear ∘ Gaussian blur) along one axis for outputs outStart ..< outStart + outCount.
    static func axisWeights(nIn: Int, nOut: Int, outStart: Int, outCount: Int, antialias: Bool) -> [Taps] {
        let factor = Double(nIn) / Double(nOut)
        var kernel: [Double] = [1]
        if antialias {
            let sigma = max((factor - 1) / 2, 0.001)
            var ks = Int(max(2.0 * 2 * sigma, 3))
            if ks % 2 == 0 { ks += 1 }
            let half = ks / 2
            kernel = (0..<ks).map { t in
                let x = Double(t - half)
                return exp(-(x * x) / (2 * sigma * sigma))
            }
            let s = kernel.reduce(0, +)
            kernel = kernel.map { $0 / s }
        }
        let half = kernel.count / 2

        var rows: [Taps] = []
        rows.reserveCapacity(outCount)
        for o in outStart..<(outStart + outCount) {
            let src = max((Double(o) + 0.5) * factor - 0.5, 0)
            let i0 = Int(src.rounded(.down))
            let i1 = min(i0 + 1, nIn - 1)
            let l1 = src - Double(i0), l0 = 1 - l1
            var acc: [Int: Double] = [:]
            for (base, lw) in [(i0, l0), (i1, l1)] where lw != 0 {
                for t in 0..<kernel.count {
                    var j = base + t - half
                    if j < 0 { j = -j } else if j >= nIn { j = 2 * (nIn - 1) - j }   // reflect
                    acc[j, default: 0] += lw * kernel[t]
                }
            }
            let idx = acc.keys.sorted()
            rows.append(Taps(indices: idx, weights: idx.map { Float(acc[$0]!) }))
        }
        return rows
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }

    // MARK: - Decoding

    /// Full-resolution image with EXIF orientation applied.
    static func uprightImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(w, h),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Interleaved 8-bit RGBX in the image's own colour space (no conversion).
    static func rgbaBytes(_ image: CGImage) throws -> ([UInt8], Int, Int) {
        let w = image.width, h = image.height
        let space: CGColorSpace
        if let s = image.colorSpace, s.model == .rgb { space = s }
        else { space = CGColorSpace(name: CGColorSpace.sRGB)! }
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { throw Failure.unsupportedPixelFormat }
        return (rgba, w, h)
    }
}
