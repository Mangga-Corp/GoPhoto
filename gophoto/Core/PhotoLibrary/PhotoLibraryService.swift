//
//  PhotoLibraryService.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 11/10/26.
//
//
//  PhotoLibraryService.swift
//  gophoto
//
//  Core layer: the ONLY place that talks to the Photos library.
//

import Photos

// MARK: - Errors

nonisolated enum PhotoLibraryError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "GoPhoto can't save to Photos. Allow it in Settings → GoPhoto → Photos."
        case .saveFailed:
            return "Couldn't save the photo. Please try again."
        }
    }
}

// MARK: - Protocol

nonisolated protocol PhotoLibraryServiceProtocol: AnyObject {
    func save(imageData: Data) async throws -> String?
}

// MARK: - Real implementation

nonisolated final class PhotoLibraryService: PhotoLibraryServiceProtocol, @unchecked Sendable {

    func save(imageData: Data) async throws -> String? {
        // Shows the iOS popup the first time; afterwards it returns the saved answer instantly
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else {
            throw PhotoLibraryError.permissionDenied
        }
        nonisolated(unsafe) var assetID: String?
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                // Save the ORIGINAL file (keeps full quality + metadata)
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
                assetID = request.placeholderForCreatedAsset?.localIdentifier
            }
        } catch {
            throw PhotoLibraryError.saveFailed
        }
        return assetID
    }
}
