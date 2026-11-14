import ImageIO
import UIKit

nonisolated enum FaceCrop {
    static let margin: CGFloat = 0.3
    static let maxPixels: CGFloat = 512

    /// The whole thumbnail, upright.
    static func thumbnail(at url: URL) -> UIImage? {
        decode(url).map { UIImage(cgImage: $0) }
    }

    /// A face cut out of a thumbnail. `face` is normalized, origin top-left.
    static func image(at url: URL, face: CGRect) -> UIImage? {
        guard let image = decode(url) else { return nil }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let pixels = CGRect(x: face.minX * width, y: face.minY * height,
                            width: face.width * width, height: face.height * height)
            .insetBy(dx: -face.width * width * margin, dy: -face.height * height * margin)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
            .integral
        return image.cropping(to: pixels).map { UIImage(cgImage: $0) }
    }

    private static func decode(_ url: URL) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
