//
//  GalleryViewModel.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  Gallery screen state: Photos access + thumbnails.
//  The photo list itself comes from @Query in the View.

import Observation
import UIKit
import UniformTypeIdentifiers

@Observable
final class GalleryViewModel {

    private(set) var access: PhotoAccess = .notDetermined
    
    private let authorization: PhotoAuthorizationProtocol

    private let imageLoader: ImageLoaderProtocol
    
    private let gallerySync: GallerySync
    
    private let photoDeleter: PhotoDeleterProtocol
    private let galleryStore: GalleryStoreProtocol
    private let photoLibraryService: PhotoLibraryServiceProtocol
    var deleteErrorMessage: String?
    init(authorization: PhotoAuthorizationProtocol = PhotoAuthorization(),
         imageLoader: ImageLoaderProtocol = ImageLoader(),
         gallerySync: GallerySync? = nil,
         photoDeleter: PhotoDeleterProtocol = PhotoDeleter(),
         galleryStore: GalleryStoreProtocol? = nil,
         photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService()) {
        self.authorization = authorization
        self.imageLoader = imageLoader
        self.gallerySync = gallerySync ?? GallerySync()
        self.photoDeleter = photoDeleter
        self.galleryStore = galleryStore ?? GalleryStore()
        self.photoLibraryService = photoLibraryService
        // Known right away (a cheap status read): the first frame already shows the grid or the
        // empty state instead of a loading spinner.
        self.access = authorization.currentAccess()
    }

    func onAppear() async {
        if access == .notDetermined {
            access = await authorization.requestAccess()
        }
        await removeDeletedPhotos()
    }
    
    func removeDeletedPhotos() async {
        guard access == .allowed else { return }
        await gallerySync.removeDeletedPhotosInBackground()
    }

    /// Looks up all photos in one request and builds missing thumbnails in the background.
    func prepareThumbnails(for assetIDs: [String]) async {
        guard access == .allowed else { return }
        await imageLoader.prepareThumbnails(for: assetIDs)
    }

    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
        await imageLoader.thumbnail(for: assetID, targetSize: targetSize)
    }
    func fullImage(for assetID: String, targetSize: CGSize ) async -> UIImage? {
        await imageLoader.fullImage(for: assetID, targetSize: targetSize)
    }

    func delete(assetIDs: [String]) async -> Bool {
        guard !assetIDs.isEmpty else { return false }
        do {
            try await photoDeleter.delete(assetIDs: assetIDs)
            galleryStore.remove(assetIDs: assetIDs)
            ThumbnailCache.shared.remove(assetIDs: assetIDs)
            return true
        } catch let error where error.isUserCancelled {
            return false
        } catch {
            deleteErrorMessage = assetIDs.count == 1
                ? "Couldn't delete this photo. Please try again."
                : "Couldn't delete these photos. Please try again."
            return false
        }
    }

    func delete(assetID: String) async -> Bool {
        await delete(assetIDs: [assetID])
    }

    /// Renders the photo at full resolution with the manually adjusted `settings` and saves it as a
    /// NEW photo in Photos and the gallery. The original is untouched, so it is always the way back.
    /// Returns an error message, or nil on success.
    func saveEdited(assetID: String, presetID: UUID?, settings: PhotoEnhancer.Settings) async -> String? {
        do {
            let source = try await PhotoExport.data(for: assetID, as: .jpeg)
            let output: Data? = await Task.detached(priority: .userInitiated) {
                CapturedPhotoEnhancing.enhance(source, with: PhotoEnhancer(settings: settings))
                    .flatMap { CapturedPhotoEnhancing.file(for: $0, metadataFrom: source) }
            }.value
            guard let output else { return PhotoExportError.unreadable.localizedDescription }
            guard let newID = try await photoLibraryService.save(imageData: output) else {
                return PhotoLibraryError.saveFailed.localizedDescription
            }
            // Thumbnail first (off the main thread), so the new photo appears sharp right away
            await Task.detached(priority: .userInitiated) {
                ThumbnailCache.shared.store(imageData: output, for: newID)
            }.value
            galleryStore.addCaptured(assetID: newID, presetID: presetID)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
