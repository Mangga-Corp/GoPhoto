//
//  GalleryStore.swift
//  gophoto
//
//  Created by Reynard Setiawan on 13/10/26.
//
//  Writes gallery records. Used by the camera after a photo is saved (DBM-78).

import Foundation
import SwiftData

protocol GalleryStoreProtocol: AnyObject {
    ///   - assetID: localIdentifier returned by PhotoLibraryService.save
    ///   - presetID: active preset, nil until presets exist
    func addCaptured(assetID: String, presetID: UUID?)
}

final class GalleryStore: GalleryStoreProtocol {
    private let context: ModelContext

    init(context: ModelContext? = nil) {
        // mainContext is MainActor-only, so read it here (inside the init body),
        // not in the default parameter value.
        self.context = context ?? AppDatabase.container.mainContext
    }

    func addCaptured(assetID: String, presetID: UUID?) {
        context.insert(GalleryPhoto(assetID: assetID, presetID: presetID))
        try? context.save()
    }
}

// MARK: - Mock (Previews & tests only)

#if DEBUG
final class MockGalleryStore: GalleryStoreProtocol {
    /// IDs passed in, so tests can check what was recorded
    private(set) var addedIDs: [String] = []

    func addCaptured(assetID: String, presetID: UUID?) {
        addedIDs.append(assetID)
    }
}
#endif // DEBUG
