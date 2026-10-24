//
//  CapturedPhotoEnhancing.swift
//  gophoto
//
//  Bridges `PhotoEnhancer` (ported from ai-model-kevin, written for upright frames) to the
//  camera's photo files: decode upright, enhance, and write back a file with the original's
//  metadata (date, lens, location), so the saved photo is a normal camera photo.
//

import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

nonisolated enum CapturedPhotoEnhancing {

    /// The photo file decoded upright (EXIF orientation applied), full resolution.
    static func uprightImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // applies the orientation
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }

    /// The camera file cropped (centred) to `aspect` (width / height of the upright photo), written
    /// with the original's metadata. Nil if it could not be decoded or encoded. Heavy: off the main actor.
    static func cropped(_ data: Data, aspect: Double) -> Data? {
        guard aspect > 0, let upright = uprightImage(from: data), let cgImage = upright.cgImage else { return nil }
        let w = Double(cgImage.width), h = Double(cgImage.height)
        let rect: CGRect
        if w / h > aspect {
            let width = h * aspect
            rect = CGRect(x: (w - width) / 2, y: 0, width: width, height: h)
        } else {
            let height = w / aspect
            rect = CGRect(x: 0, y: (h - height) / 2, width: w, height: height)
        }
        guard let crop = cgImage.cropping(to: rect.integral) else { return nil }
        return file(for: UIImage(cgImage: crop), metadataFrom: data)
    }

    /// The enhanced photo of a camera file, upright. Nil if it could not be decoded or rendered.
    /// Heavy: call off the main actor.
    static func enhance(_ data: Data, with enhancer: PhotoEnhancer = PhotoEnhancer()) -> UIImage? {
        guard let upright = uprightImage(from: data) else { return nil }
        return enhancer.enhance(upright)
    }

    /// `image` (upright) written in the original file's format with its metadata; the orientation
    /// tag is reset because the pixels are already upright. Nil if it could not be encoded.
    static func file(for image: UIImage, metadataFrom original: Data, quality: Double = 0.9) -> Data? {
        guard let cgImage = image.cgImage,
              let source = CGImageSourceCreateWithData(original as CFData, nil) else { return nil }
        let type = CGImageSourceGetType(source) ?? (UTType.jpeg.identifier as CFString)
        var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        properties[kCGImagePropertyOrientation] = 1
        if var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            properties[kCGImagePropertyTIFFDictionary] = tiff
        }
        properties[kCGImagePropertyPixelWidth] = nil
        properties[kCGImagePropertyPixelHeight] = nil
        if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            exif[kCGImagePropertyExifPixelXDimension] = cgImage.width
            exif[kCGImagePropertyExifPixelYDimension] = cgImage.height
            properties[kCGImagePropertyExifDictionary] = exif
        }
        properties[kCGImageDestinationLossyCompressionQuality] = quality

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
