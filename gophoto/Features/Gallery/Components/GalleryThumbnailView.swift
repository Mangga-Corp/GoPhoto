//
//  GalleryThumbnailView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  One square cell in the gallery grid. Plain values in, no ViewModel.

import SwiftUI

struct GalleryThumbnailView: View {
    let assetID: String
    let createdAt: Date
    let loadThumbnail: (String, CGSize) async -> UIImage?

    /// Cell is ~1/3 of screen width; ask a bit bigger so it stays sharp
    private let thumbnailPoints: CGFloat = 150

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if isMissing {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(Text("Photo, \(createdAt.formatted(date: .abbreviated, time: .shortened))"))
            .task(id: assetID) {
                let pixels = thumbnailPoints * displayScale
                image = await loadThumbnail(assetID, CGSize(width: pixels, height: pixels))
                isMissing = (image == nil)
            }
    }
}
