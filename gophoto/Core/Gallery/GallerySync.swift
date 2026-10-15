//
//  GallerySync.swift
//  gophoto
//
//  Created by Reynard Setiawan on 14/10/26.
//
//  Keeps the app gallery in sync with the Photos app:
//  removes records whose photo was deleted in Photos.
//

import Photos
import SwiftData

final class GallerySync {
    private let context: ModelContext

    /// Pass a context in tests/previews; nil = the app's shared database.
    init(context: ModelContext? = nil) {
        self.context = context ?? AppDatabase.container.mainContext
    }

    /// Removes gallery records whose photo no longer exists in Photos.
    /// Cheap and safe to call often (gallery opens, app becomes active).
    func removeDeletedPhotos() {
        // 1. SAFETY: only with Photos access. Without access every photo looks "missing",
        //    and we would wipe the whole gallery.
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return }

        // 2. Every photo ID the gallery knows
        guard let records = try? context.fetch(FetchDescriptor<GalleryPhoto>()),
              !records.isEmpty else { return }

        // 3. Ask Photos which of them still exist (one request for all IDs)
        let found = PHAsset.fetchAssets(withLocalIdentifiers: records.map(\.assetID), options: nil)
        var existingIDs = Set<String>()
        found.enumerateObjects { asset, _, _ in
            existingIDs.insert(asset.localIdentifier)
        }

        // 4. Delete the records whose photo is gone (the Photos library is never touched here)
        for record in records where !existingIDs.contains(record.assetID) {
            context.delete(record)
        }
        try? context.save()
    }
}
