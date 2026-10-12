//
//  ChoosePhotos.swift
//  gophoto
//
//  Created by Sebastian Darren on 12/10/26.
//

import Photos
import UIKit

final class ChoosePhotosService {
    private let imageManager = PHCachingImageManager()

    var access: PhotoAccess { Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite)) }

    func requestAccess(completion: @escaping (PhotoAccess) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async { completion(Self.map(status)) }
        }
    }

    func fetchAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    @discardableResult
    func thumbnail(for asset: PHAsset, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        return imageManager.requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                         contentMode: .aspectFill, options: options) { image, _ in
            DispatchQueue.main.async { completion(image) }
        }
    }

    func cancel(_ id: PHImageRequestID) { imageManager.cancelImageRequest(id) }

    /// Loads selected assets (max 1024 px) in the same order as `assets`.
    func loadItems(for assets: [PHAsset], completion: @escaping (Result<[PhotoItem], Error>) -> Void) {
        var results = [PhotoItem?](repeating: nil, count: assets.count)
        var failed = false
        let group = DispatchGroup()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        for (index, asset) in assets.enumerated() {
            group.enter()
            imageManager.requestImage(for: asset, targetSize: CGSize(width: 1024, height: 1024),
                                      contentMode: .aspectFit, options: options) { image, info in
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                DispatchQueue.main.async {
                    if let image { results[index] = PhotoItem(image: image) } else { failed = true }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) {
            failed ? completion(.failure(PhotoError.loadFailed)) : completion(.success(results.compactMap { $0 }))
        }
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotoAccess {
        switch status {
        case .authorized: return .authorized
        case .limited: return .limited
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

