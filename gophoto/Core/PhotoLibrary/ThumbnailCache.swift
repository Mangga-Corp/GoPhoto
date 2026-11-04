//
//  ThumbnailCache.swift
//  gophoto
//
//  Two-level thumbnail cache for the gallery (like the Photos app's own derivatives):
//  1. memory (NSCache)  → instant, lost when the app is killed
//  2. disk (Caches/)    → survives restarts, decoded with ImageIO at the size the cell needs
//
//  A thumbnail is written the moment a photo is captured/edited, from the data we already hold,
//  so the gallery never has to ask Photos for the photos the user just took.
//  Everything here is thread-safe and runs off the main thread.
//

import UIKit
import ImageIO
import UniformTypeIdentifiers

nonisolated final class ThumbnailCache: @unchecked Sendable {

    static let shared = ThumbnailCache()

    /// Longest side (pixels) of the file kept on disk. Covers a 3-column grid on a 3× screen
    /// (≈ 400 px) with room to spare, so grid thumbnails are always sharp.
    static let storedPixels: CGFloat = 640

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 96 * 1024 * 1024   // ~96 MB of decoded pixels
        return cache
    }()

    private let directory: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("GalleryThumbnails-v2", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Drop the files of the first version (some were decoded too small)
        try? FileManager.default.removeItem(at: base.appendingPathComponent("GalleryThumbnails", isDirectory: true))
    }

    // MARK: - Read

    /// Memory only: cheap enough to call while a view is being built (no flash of grey).
    func cachedImage(for assetID: String, maxPixels: CGFloat) -> UIImage? {
        memory.object(forKey: key(assetID, Self.bucket(maxPixels)))
    }

    /// Memory first, then disk. nil if this photo has no stored thumbnail yet.
    func image(for assetID: String, maxPixels requested: CGFloat) -> UIImage? {
        let maxPixels = Self.bucket(requested)
        let memoryKey = key(assetID, maxPixels)
        if let hit = memory.object(forKey: memoryKey) { return hit }

        guard let image = Self.downsampledImage(at: fileURL(for: assetID), maxPixels: maxPixels) else {
            return nil
        }
        memory.setObject(image, forKey: memoryKey, cost: Self.cost(of: image))
        return image
    }

    // MARK: - Write

    /// Encodes a ready-to-store thumbnail from a photo file (capture / edit). Heavy for a 48 MP
    /// photo: call off the main thread. Can run BEFORE the photo has an asset ID, in parallel
    /// with the save to Photos; then `store(encoded:for:)` once the ID is known.
    static func encodedThumbnail(from imageData: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let thumbnail = downsample(source, maxPixels: storedPixels) else { return nil }
        return encode(thumbnail)
    }

    /// Writes a thumbnail made by `encodedThumbnail(from:)`.
    func store(encoded: Data, for assetID: String) {
        try? encoded.write(to: fileURL(for: assetID), options: .atomic)
    }

    /// Builds and stores the thumbnail from a photo file. Never touches Photos. Off the main thread.
    func store(imageData: Data, for assetID: String) {
        guard let encoded = Self.encodedThumbnail(from: imageData) else { return }
        store(encoded: encoded, for: assetID)
    }

    /// Stores an image that came from Photos (photos taken before this cache existed).
    func store(image: UIImage, for assetID: String) {
        guard let cgImage = image.cgImage else { return }
        write(cgImage, for: assetID)
    }

    func remove(assetIDs: [String]) {
        for id in assetIDs {
            try? FileManager.default.removeItem(at: fileURL(for: id))
        }
        // Memory entries are keyed by size; they are cheap and drop out on their own.
    }

    func hasStoredThumbnail(for assetID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: assetID).path)
    }

    // MARK: - Private

    private func write(_ cgImage: CGImage, for assetID: String) {
        guard let data = Self.encode(cgImage) else { return }
        store(encoded: data, for: assetID)
    }

    private static func encode(_ cgImage: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, cgImage,
                                   [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func key(_ assetID: String, _ maxPixels: CGFloat) -> NSString {
        "\(assetID)#\(Int(maxPixels.rounded()))" as NSString
    }

    /// localIdentifiers contain "/" → make a safe file name.
    private func fileURL(for assetID: String) -> URL {
        let safe = Data(assetID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(safe + ".jpg")
    }

    /// Rounds the size up to a multiple of 32 px (never above the stored size) so a cell that
    /// is 1 px wider still hits the cache. The stored file is never upscaled.
    private static func bucket(_ pixels: CGFloat) -> CGFloat {
        min(max((pixels / 32).rounded(.up) * 32, 64), storedPixels)
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private static func downsampledImage(at url: URL, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = downsample(source, maxPixels: maxPixels) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// ImageIO decodes straight to the small size (no full-size bitmap), and applies the EXIF
    /// orientation so the thumbnail is upright.
    private static func downsample(_ source: CGImageSource, maxPixels: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,    // decode now, on this background thread
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
