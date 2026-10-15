//
//  PhotoPagerView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 14/10/26.
//
//  full-screen viewer. Swipe left/right between gallery photos, like the Photos app.

import SwiftUI

struct PhotoPagerView: View {
    
    let photos: [GalleryPhoto]
    let loadImage: (String, CGSize) async -> UIImage?
    let loadThumbnail: (String,CGSize) async -> UIImage?
    /// assetID of the image currently on screen
    @State private var currentID: String

    /// - Parameter startID: assetID of the photo that was tapped in the grid
    init(photos: [GalleryPhoto],
         startID: String,
         loadImage: @escaping (String, CGSize) async -> UIImage?,
    loadThumbnail: @escaping (String, CGSize) async -> UIImage?) {
        self.photos = photos
        self.loadImage = loadImage
        self.loadThumbnail = loadThumbnail
        _currentID = State(initialValue: startID)
    }

    var body: some View {
        TabView(selection: $currentID) {
            ForEach(photos) { photo in
                FullPhotoView(assetID: photo.assetID,
                              createdAt: photo.createdAt,
                              loadImage: loadImage)
                    .tag(photo.assetID)          // links the page to currentID
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))   // swipe pages, no dots (like Photos)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom){
            PhotoStripView(photos: photos,
                           currentID: $currentID,
                           loadThumbnail: loadThumbnail,).background(.bar)
        }
    }

    /// Date + time of the photo on screen, shown in the nav bar like the Photos app
    private var title: String {
        guard let photo = photos.first(where: { $0.assetID == currentID }) else { return "" }
        return photo.createdAt.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Previews (Debug only)

#if DEBUG
extension GalleryPhoto {
    /// Fake records for Previews (not saved anywhere), newest first
    static func previewSamples(_ count: Int) -> [GalleryPhoto] {
        (0..<count).map { i in
            GalleryPhoto(assetID: "asset-\(i)",
                         createdAt: .now.addingTimeInterval(Double(-i) * 60))
        }
    }
}

#Preview {
    NavigationStack {
        PhotoPagerView(photos: GalleryPhoto.previewSamples(5),
                       startID: "asset-2",
                       loadImage: MockImageLoader().fullImage,
                       loadThumbnail: MockImageLoader().thumbnail)
    }
}
#endif // DEBUG
