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
    var onFinish: (([PhotoItem]) -> Void)? 

    let canRemoveExisting: Bool

    private let service: ChoosePhotosService
    private let limit: Int
    private let existing: [PhotoItem]
    private let existingIDs: Set<String>
    private var assets: PHFetchResult<PHAsset>
    private var visibleExisting: PHFetchResult<PHAsset>

    init(service: ChoosePhotosService, existing: [PhotoItem], limit: Int, canRemoveExisting: Bool) {
        let ids = Set(existing.compactMap(\.sourceAssetIdentifier))
        self.service = service
        self.existing = existing
        self.existingIDs = ids
        self.limit = limit
        self.canRemoveExisting = canRemoveExisting
        self.assets = service.fetchAssets()
        self.visibleExisting = PHAsset.fetchAssets(withLocalIdentifiers: Array(ids), options: nil)
    }

    var count: Int { assets.count }

    var isLimitedAccess: Bool { service.access == .limited }

    func reload() {
        assets = service.fetchAssets()
        visibleExisting = PHAsset.fetchAssets(withLocalIdentifiers: Array(existingIDs), options: nil)
    }

    func identifier(at index: Int) -> String { assets.object(at: index).localIdentifier }

    func isAlreadyAdded(at index: Int) -> Bool { existingIDs.contains(identifier(at: index)) }

    func alreadyAddedIndexes() -> [Int] {
        var indexes: [Int] = []
        visibleExisting.enumerateObjects { asset, _, _ in
            let index = self.assets.index(of: asset)
            if index != NSNotFound { indexes.append(index) }
        }
        return indexes
    }

    /// Returns a closure that cancels the request.
    func loadThumbnail(at index: Int, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> () -> Void {
        let id = service.thumbnail(for: assets.object(at: index), side: side, completion: completion)
        return { [service] in service.cancel(id) }
    }

    func canSelect(currentCount: Int) -> Bool {
        guard hasRoom(currentCount: currentCount) else {
            onError?("A preference can have up to \(limit) photos.")
            return false
        }
        return true
    }

    func hasRoom(currentCount: Int) -> Bool { currentCount + hiddenExistingCount < limit }

    func done(selectedIndexes: [Int]) {
        let selectedIDs = Set(selectedIndexes.map(identifier(at:)))
        var visibleIDs = Set<String>()
        visibleExisting.enumerateObjects { asset, _, _ in visibleIDs.insert(asset.localIdentifier) }

        let kept = existing.filter { item in
            guard let id = item.sourceAssetIdentifier, visibleIDs.contains(id) else { return true }
            return selectedIDs.contains(id)
        }
        let newAssets = selectedIndexes.sorted()
            .map { assets.object(at: $0) }
            .filter { !existingIDs.contains($0.localIdentifier) }

        guard !newAssets.isEmpty else { onFinish?(kept); return }
        onLoadingChange?(true)
        service.loadItems(for: newAssets) { [weak self] result in
            guard let self else { return }
            self.onLoadingChange?(false)
            switch result {
            case .success(let items): self.onFinish?(kept + items)
            case .failure(let error): self.onError?(error.localizedDescription)
            }
        }
    }

    private var hiddenExistingCount: Int { existing.count - visibleExisting.count }
}
