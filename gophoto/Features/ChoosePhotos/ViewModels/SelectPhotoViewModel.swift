//
//  SelectPhotoViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Photos
import UIKit

final class SelectPhotoViewModel {
    var onLoadingChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onFinish: (([PhotoItem]) -> Void)?   // empty array = nothing selected

    private let service: ChoosePhotosService
    private let remaining: Int
    private let limit: Int
    private let assets: PHFetchResult<PHAsset>

    init(service: ChoosePhotosService, remaining: Int, limit: Int) {
        self.service = service
        self.remaining = remaining
        self.limit = limit
        self.assets = service.fetchAssets()
    }

    var count: Int { assets.count }

    func identifier(at index: Int) -> String { assets.object(at: index).localIdentifier }

    /// Returns a closure that cancels the request.
    func loadThumbnail(at index: Int, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> () -> Void {
        let id = service.thumbnail(for: assets.object(at: index), side: side, completion: completion)
        return { [service] in service.cancel(id) }
    }

    func canSelect(currentCount: Int) -> Bool {
        guard currentCount < remaining else {
            onError?("You can add \(remaining) more photo(s). The limit is \(limit).")
            return false
        }
        return true
    }

    func done(selectedIndexes: [Int]) {
        let picked = selectedIndexes.sorted().map { assets.object(at: $0) }
        guard !picked.isEmpty else { onFinish?([]); return }
        onLoadingChange?(true)
        service.loadItems(for: picked) { [weak self] result in
            self?.onLoadingChange?(false)
            switch result {
            case .success(let items): self?.onFinish?(items)
            case .failure(let error): self?.onError?(error.localizedDescription)
            }
        }
    }
}
