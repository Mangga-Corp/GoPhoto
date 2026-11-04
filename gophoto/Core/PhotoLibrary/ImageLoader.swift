//
//  ImageLoader.swift
//  gophoto
//
//  Loads images from the Photos library for the gallery, viewer and editor.
//
//  Thumbnails (grid, strip, look previews):
//    memory cache → disk cache (ThumbnailCache) → Photos (only the first time, then cached).
//    Photos taken or edited in the app already have their thumbnail on disk (written at save
//    time), so the gallery opens without waiting on Photos at all.
//  Full images: straight from Photos at the requested size.
//
//  Everything heavy is @concurrent: it runs on a background thread, never the main thread.
//

import Photos
import UIKit

/// Protocol for image loader (real/mock)
nonisolated protocol ImageLoaderProtocol: AnyObject, Sendable {
    /// targetSize in PIXELS (points × screen scale). Returns nil if the photo no longer exists.
    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage?
    func fullImage(for assetID: String, targetSize: CGSize) async -> UIImage?
    /// Call when the gallery opens: looks up all photos in ONE request and builds the missing
    /// thumbnails in the background (newest first), so scrolling never waits.
    func prepareThumbnails(for assetIDs: [String]) async
}

nonisolated final class ImageLoader: ImageLoaderProtocol, @unchecked Sendable {

    /// Shared so every screen reuses the same Photos cache and lookups.
    private static let shared = State()

    private let cache = ThumbnailCache.shared

    // MARK: - Thumbnails

    @concurrent
    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
        let maxPixels = max(targetSize.width, targetSize.height)
        if let image = cache.image(for: assetID, maxPixels: maxPixels) { return image }

        // Not stored yet (photo from before the cache existed): build it once from Photos
        guard await Self.shared.buildThumbnail(for: assetID, cache: cache) else { return nil }
        return cache.image(for: assetID, maxPixels: maxPixels)
    }

    @concurrent
    func prepareThumbnails(for assetIDs: [String]) async {
        let missing = assetIDs.filter { !cache.hasStoredThumbnail(for: $0) }
        guard !missing.isEmpty else { return }

        // One lookup for every missing photo instead of one per cell
        Self.shared.resolve(missing)

        // A few at a time: fast, but leaves Photos free for the cells on screen
        await withTaskGroup(of: Void.self) { group in
            var iterator = missing.makeIterator()
            for _ in 0..<3 {
                guard let id = iterator.next() else { break }
                group.addTask { _ = await Self.shared.buildThumbnail(for: id, cache: self.cache) }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, let id = iterator.next() else { continue }
                group.addTask { _ = await Self.shared.buildThumbnail(for: id, cache: self.cache) }
            }
        }
    }

    // MARK: - Full images

    @concurrent
    func fullImage(for assetID: String, targetSize: CGSize) async -> UIImage? {
        guard let asset = Self.shared.asset(for: assetID) else { return nil }
        return await Self.shared.request(asset, targetSize: targetSize, contentMode: .aspectFit)
    }

    // MARK: - Shared state (asset lookups + Photos manager + in-flight work)

    private final class State: @unchecked Sendable {
        private let manager = PHCachingImageManager()
        private let lock = NSLock()
        private var assets: [String: PHAsset] = [:]
        private var inFlight: [String: Task<Bool, Never>] = [:]

        /// One PhotoKit request for many IDs.
        func resolve(_ ids: [String]) {
            lock.lock()
            let unknown = ids.filter { assets[$0] == nil }
            lock.unlock()
            guard !unknown.isEmpty else { return }

            let result = PHAsset.fetchAssets(withLocalIdentifiers: unknown, options: nil)
            var found: [String: PHAsset] = [:]
            result.enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset }

            lock.lock()
            assets.merge(found) { _, new in new }
            lock.unlock()
        }

        func asset(for id: String) -> PHAsset? {
            lock.lock()
            if let known = assets[id] { lock.unlock(); return known }
            lock.unlock()
            resolve([id])
            lock.lock(); defer { lock.unlock() }
            return assets[id]
        }

        /// Downloads the thumbnail from Photos and stores it. Cells and the background warm-up
        /// asking for the same photo share one request.
        func buildThumbnail(for id: String, cache: ThumbnailCache) async -> Bool {
            lock.lock()
            if let running = inFlight[id] { lock.unlock(); return await running.value }
            let task = Task<Bool, Never> { [self] in
                defer { lock.lock(); inFlight[id] = nil; lock.unlock() }
                guard let asset = asset(for: id) else { return false }
                let side = ThumbnailCache.storedPixels
                guard let image = await request(asset, targetSize: CGSize(width: side, height: side),
                                                contentMode: .aspectFill) else { return false }
                cache.store(image: image, for: id)
                return true
            }
            inFlight[id] = task
            lock.unlock()
            return await task.value
        }

        func request(_ asset: PHAsset, targetSize: CGSize, contentMode: PHImageContentMode) async -> UIImage? {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat   // one callback, full sharpness
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true       // photo may be iCloud-only
            return await withCheckedContinuation { continuation in
                manager.requestImage(for: asset, targetSize: targetSize,
                                     contentMode: contentMode, options: options) { image, _ in
                    continuation.resume(returning: image)
                }
            }
        }
    }
}

///This is for mock, use in debug mode
#if DEBUG

nonisolated final class MockImageLoader: ImageLoaderProtocol, @unchecked Sendable {
    /// IDs that behave like deleted photos (returns nil → placeholder)
    var missingIDs: Set<String> = []

    /// Set value to fake loading
    var delay: Duration = .zero
    
    init (missingIDs: Set<String> = [], delay: Duration = .zero){
        self.missingIDs = missingIDs
        self.delay = delay
    }
    
    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
        if delay > .zero { try? await Task.sleep(for: delay) }
        guard !missingIDs.contains(assetID) else { return nil }
        return Self.solidImage(seed: assetID, size: targetSize)
    }
    func prepareThumbnails(for assetIDs: [String]) async {}
    func fullImage(for assetID: String, targetSize: CGSize) async -> UIImage? {
        await fakeImage(for: assetID, size: CGSize(width: targetSize.width, height: targetSize.width * 4 / 3))
    }
    
    private func fakeImage(for assetID: String, size: CGSize) async -> UIImage? {
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !missingIDs.contains(assetID) else { return nil }
            return Self.solidImage(seed: assetID, size: size)
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

