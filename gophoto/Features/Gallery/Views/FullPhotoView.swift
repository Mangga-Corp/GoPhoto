//
//  FullPhotoView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 13/10/26.
//
//  One photo in the full-screen viewer (DBM-77). Plain values in, no ViewModel.
//  States: loading → photo, or "not available" if it was deleted from Photos.
//

import SwiftUI

struct FullPhotoView: View {
    let assetID: String
    let createdAt: Date
    /// (assetID, size in PIXELS) → whole image, or nil if the photo is gone
    let loadImage: (String, CGSize) async -> UIImage?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        // GeometryReader gives the page size, so we ask Photos for a screen-sized image
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()          // whole photo visible, no crop
                } else if isMissing {
                    ContentUnavailableView(
                        "Photo Not Available",
                        systemImage: "photo.badge.exclamationmark",
                        description: Text("It may have been deleted from Photos.")
                    )
                } else {
                    ProgressView()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Runs when the page appears; cancelled automatically when it scrolls away
            .task(id: assetID) {
                let pixels = CGSize(width: proxy.size.width * displayScale,
                                    height: proxy.size.height * displayScale)
                image = await loadImage(assetID, pixels)
                isMissing = (image == nil)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Photo, \(createdAt.formatted(date: .abbreviated, time: .shortened))"))
    }
}

// MARK: - Previews (Debug only)

#if DEBUG
#Preview("Photo") {
    FullPhotoView(assetID: "asset-1",
                  createdAt: .now,
                  loadImage: MockImageLoader().fullImage)
}

#Preview("Loading") {
    FullPhotoView(assetID: "asset-1",
                  createdAt: .now,
                  loadImage: MockImageLoader(delay: .seconds(60)).fullImage)
}
#Preview("Deleted") {
    FullPhotoView(assetID: "gone",
                  createdAt: .now,
                  loadImage: MockImageLoader(missingIDs: ["gone"]).fullImage)
    
}
#endif // DEBUG
