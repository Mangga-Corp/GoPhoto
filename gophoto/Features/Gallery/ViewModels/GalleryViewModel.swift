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

    init(authorization: PhotoAuthorizationProtocol = PhotoAuthorization(),
         imageLoader: ImageLoaderProtocol = ImageLoader()) {
        self.authorization = authorization
        self.imageLoader = imageLoader
    }

    func onAppear() async {
        access = authorization.currentAccess()
        if access == .notDetermined {
            access = await authorization.requestAccess()
        }
    }

    func thumbnail(for assetID: String, targetSize: CGSize) async -> UIImage? {
        await imageLoader.thumbnail(for: assetID, targetSize: targetSize)
    }
    func fullImage(for assetID: String, targetSize: CGSize ) async -> UIImage? {
        await imageLoader.fullImage(for: assetID, targetSize: targetSize)
    }
}
