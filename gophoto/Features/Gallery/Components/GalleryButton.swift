//
//  GalleryButton.swift
//  gophoto
//
//  Created by Reynard Setiawan on 13/10/26.
//
//  Bottom-left button on the camera, like the iPhone Camera app:
//  shows the newest gallery photo; tapping opens the gallery.

import SwiftUI
import SwiftData

struct GalleryShortcutButton: View {
    let action: () -> Void

    @Query(GalleryShortcutButton.newestPhoto) private var newest: [GalleryPhoto]

    @State private var loader = ImageLoader()
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    
    private let size: CGFloat = 52

    static var newestPhoto: FetchDescriptor<GalleryPhoto> {
        var descriptor = FetchDescriptor<GalleryPhoto>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    // No photo yet, or no Photos access yet
                    Image(systemName: "photo.on.rectangle")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .background(.white.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Gallery")
        .task(id: newest.first?.assetID) {
            guard let assetID = newest.first?.assetID else {
                image = nil
                return
            }
            let pixels = size * displayScale
            image = await loader.thumbnail(for: assetID, targetSize: CGSize(width: pixels, height: pixels))
        }
        .task(id: scenePhase){
            if scenePhase == .active{GallerySync().removeDeletedPhotos()}
        }
    }
}
