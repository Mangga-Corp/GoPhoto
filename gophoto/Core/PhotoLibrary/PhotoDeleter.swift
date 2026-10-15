//
//  PhotoDeleter.swift
//  gophoto
//
//  Created by Reynard Setiawan on 15/10/26.
//
//  Deletes photos from the user's Photos library.
//  iOS shows its own confirmation alert, no custom alert needed.
//

import Photos

protocol PhotoDeleterProtocol {
    /// Deletes the assets from Photos. Throws if the user cancels or deletion fails.
    func delete(assetIDs: [String]) async throws
}

final class PhotoDeleter: PhotoDeleterProtocol {
    func delete(assetIDs: [String]) async throws {
        // Nothing left in Photos (already deleted elsewhere) → skip the system alert.
        let existing = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        guard existing.count > 0 else { return }

        // The change block must be Sendable, so fetch inside it
        // (PHFetchResult isn't Sendable; [String] is).
        try await PHPhotoLibrary.shared().performChanges {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
            PHAssetChangeRequest.deleteAssets(assets)
        }
    }
}

extension Error {
    /// True when the user tapped "Don't Allow" on the system delete alert.
    var isUserCancelled: Bool {
        (self as? PHPhotosError)?.code == .userCancelled
    }
}

#if DEBUG
final class MockPhotoDeleter: PhotoDeleterProtocol {
    private(set) var deletedIDs: [String] = []
    var shouldCancel = false

    func delete(assetIDs: [String]) async throws {
        if shouldCancel { throw PHPhotosError(.userCancelled) }
        deletedIDs += assetIDs
    }
}
#endif // DEBUG
