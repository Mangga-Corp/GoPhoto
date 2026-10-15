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
    
    let onDelete: (String) async -> Bool
    /// assetID of the image currently on screen
    @State private var currentID: String
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss

    /// - Parameter startID: assetID of the photo that was tapped in the grid
    init(photos: [GalleryPhoto],
         startID: String,
         loadImage: @escaping (String, CGSize) async -> UIImage?,
    loadThumbnail: @escaping (String, CGSize) async -> UIImage?,
         onDelete: @escaping (String) async -> Bool) {
        self.photos = photos
        self.loadImage = loadImage
        self.loadThumbnail = loadThumbnail
        self.onDelete = onDelete
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: SharedPhoto(assetID: currentID),
                          preview: SharePreview("Photo", image: Image(systemName: "photo")))
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar){
                Button("Delete", systemImage: "trash", role: .destructive){
                    Task{await deleteCurrent()}
                }.disabled(isDeleting)
            }
        }
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
    
    private func deleteCurrent() async {
           isDeleting = true
           defer { isDeleting = false }

           let deletingID = currentID
           // Pick the neighbor BEFORE deleting (the list changes after).
           let nextID = neighbor(of: deletingID)

           // false = user tapped "Don't Allow" or it failed → stay on this photo
           guard await onDelete(deletingID) else { return }

           if let nextID {
               withAnimation { currentID = nextID }
           } else {
               dismiss()   // that was the last photo → back to the (now empty) grid
           }
       }

       /// The older photo next to it; if it was the oldest, the newer one; nil if it was the only one.
       private func neighbor(of id: String) -> String? {
           guard let index = photos.firstIndex(where: { $0.assetID == id }) else { return nil }
           if index + 1 < photos.count { return photos[index + 1].assetID }
           if index > 0 { return photos[index - 1].assetID }
           return nil
       }
    

}




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
                       loadThumbnail: MockImageLoader().thumbnail,
                       onDelete: { _ in true })
    }
}
#endif // DEBUG
