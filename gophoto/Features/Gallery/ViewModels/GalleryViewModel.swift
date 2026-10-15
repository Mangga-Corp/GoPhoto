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

@Observable
final class GalleryViewModel {

    private(set) var access: PhotoAccess = .notDetermined
    
    private let authorization: PhotoAuthorizationProtocol

    private let imageLoader: ImageLoaderProtocol
    
    private let gallerySync: GallerySync
    
    private let photoDeleter: PhotoDeleterProtocol
    private let galleryStore: GalleryStoreProtocol
    var deleteErrorMessage: String?
    init(authorization: PhotoAuthorizationProtocol = PhotoAuthorization(),
         imageLoader: ImageLoaderProtocol = ImageLoader(),
         gallerySync: GallerySync? = nil,
         photoDeleter: PhotoDeleterProtocol = PhotoDeleter(),
         galleryStore: GalleryStoreProtocol? = nil) {
        self.authorization = authorization
        self.imageLoader = imageLoader
        self.gallerySync = gallerySync ?? GallerySync()
        self.photoDeleter = photoDeleter
        self.galleryStore = galleryStore ?? GalleryStore()
    }

    func onAppear() async {
        access = authorization.currentAccess()
        if access == .notDetermined {
            access = await authorization.requestAccess()
        }
        removeDeletedPhotos()
    }
    
    func removeDeletedPhotos() {
           guard access == .allowed else { return }
           gallerySync.removeDeletedPhotos()
       }

    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
        await imageLoader.thumbnail(for: assetID, targetSize: targetSize)
    }
    func fullImage(for assetID: String, targetSize: CGSize ) async -> UIImage? {
        await imageLoader.fullImage(for: assetID, targetSize: targetSize)
    }
    func delete(assetID: String) async -> Bool {
        do {
            // 1. iOS asks "Allow GoPhoto to delete this photo?"
            try await photoDeleter.delete(assetIDs: [assetID])
            // 2. Only after Photos confirms, remove our record.
            galleryStore.remove(assetIDs: [assetID])
            return true
        } catch let error where error.isUserCancelled {
            // User tapped "Don't Allow": not an error, stay quiet.
            return false
        } catch {
            deleteErrorMessage = "Couldn't delete this photo. Please try again."
            return false
        }
    }
}
