//
//  GalleryThumbnailView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  One square cell in the gallery grid. Plain values in, no ViewModel.
//  A thumbnail that is already in memory shows on the very first frame (no grey flash while
//  scrolling back); otherwise it loads in the background and fades in.

import SwiftUI

struct GalleryThumbnailView: View {
    let assetID: String
    let createdAt: Date
    let loadThumbnail: (String, CGSize) async -> UIImage?
    /// Side of the cell in POINTS; the request is this × screen scale, so it is exactly sharp.
    var side: CGFloat = 132

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        Color(.secondarySystemFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = memoryHit ?? image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if isMissing {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                }
            }
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(Text("Photo, \(createdAt.formatted(date: .abbreviated, time: .shortened))"))
            // Keyed by size too: if the cell is measured after the first load, it reloads sharp
            .task(id: LoadKey(assetID: assetID, pixels: Int(pixels))) {
                if let memoryHit { image = memoryHit; return }
                let size = CGSize(width: pixels, height: pixels)
                let loaded = await loadThumbnail(assetID, size)
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
                isMissing = (loaded == nil)
            }
    }

    private struct LoadKey: Hashable {
        let assetID: String
        let pixels: Int
    }

    /// Never request below 120 pt: a size measured mid-transition must not give a blurry image.
    private var pixels: CGFloat { max(side, 120) * displayScale }

    private var memoryHit: UIImage? {
        ThumbnailCache.shared.cachedImage(for: assetID, maxPixels: pixels)
    }
}
