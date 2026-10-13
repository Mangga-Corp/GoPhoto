//
//  ImageLoader.swift
//  gophoto
//
//
import Photos
import UIKit

    ///protocol for image loader (real/mock)
protocol ImageLoaderProtocol: AnyObject {
    /// targetSize sesuai besar thumbnail yang dibutuhkan (Pixel (points x screen scale))
    /// Return nil if image with certain assetID not found
        func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage?
}


final class ImageLoader: ImageLoaderProtocol {

    /// Apple's image manager for grids; reuses work between requests
    private let manager = PHCachingImageManager()

    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
    
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            return nil
        }

        // Request options
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat  // result handler is called ONCE → safe with continuation
        options.resizeMode = .fast                 // fast resize is fine for small thumbnails
        options.isNetworkAccessAllowed = true      // photo may be iCloud-only (Optimize iPhone Storage)

        // Bridge Photos' callback API to async/await
        return await withCheckedContinuation { continuation in
            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,           // fill the square cell
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
    
}///This is for mock, use in debug mode
#if DEBUG

final class MockImageLoader: ImageLoaderProtocol {
    /// IDs that behave like deleted photos (returns nil → placeholder)
    var missingIDs: Set<String> = []

    /// Set value to fake loading
    var delay: Duration = .zero

    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard !missingIDs.contains(assetID) else { return nil }
        return Self.solidImage(seed: assetID, size: targetSize)
    }

    /// A solid-colour image; same ID → same colour
    private static func solidImage(seed: String, size: CGSize) -> UIImage {
        let hue = CGFloat(abs(seed.hashValue) % 360) / 360
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // targetSize is already in pixels
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(hue: hue, saturation: 0.5, brightness: 0.85, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif

