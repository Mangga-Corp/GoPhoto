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
    /// AI Enhanced look shown on the photo, or nil for the photo as it is in Photos.
    /// Only a preview: nothing is saved until the user shares / saves it.
    var look: EnhancedLook? = nil
    /// Manual slider settings; while set they replace `look` and re-render live.
    var adjustments: PhotoEnhancer.Settings? = nil

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var isMissing = false
    @State private var isSharp = false
    /// The rendered preview and the recipe it was rendered with (a stale look is never shown)
    @State private var filtered: (recipe: Recipe, image: UIImage)?
    @State private var isFiltering = false

    /// Re-render when the look changes or the loaded image is swapped (sharper version on zoom).
    private struct RenderKey: Equatable {
        let recipe: Recipe
        let image: ObjectIdentifier?
    }

    private struct Recipe: Equatable {
        let look: EnhancedLook?
        let settings: PhotoEnhancer.Settings?
    }

    private var recipe: Recipe { Recipe(look: look, settings: adjustments) }

    var body: some View {
        // GeometryReader gives the page size, so we ask Photos for a screen-sized image
        GeometryReader { proxy in
            ZStack {
                if let image {
                    // Pinch / double-tap to zoom, pan while zoomed
                    ZoomableImageView(image: (filtered.flatMap { $0.recipe == recipe || adjustments != nil ? $0.image : nil }) ?? image) {
                        loadSharperImage(screenSize: proxy.size)
                    }
                    .overlay(alignment: .top) {
                        if isFiltering {
                            ProgressView().padding(8).background(.regularMaterial, in: Capsule()).padding(.top, 8)
                        }
                    }
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
        .task(id: RenderKey(recipe: recipe, image: image.map(ObjectIdentifier.init))) {
            await renderLook()
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Photo, \(createdAt.formatted(date: .abbreviated, time: .shortened))"))
   
    }
    private func renderLook() async {
        let recipe = recipe
        guard recipe.look != nil || recipe.settings != nil, let source = image else {
            filtered = nil
            return
        }
        // Slider drags change the recipe many times a second: let the last one win
        if recipe.settings != nil {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
        }
        isFiltering = true
        defer { isFiltering = false }
        let result: UIImage? = await Task.detached(priority: .userInitiated) {
            if let settings = recipe.settings {
                PhotoEnhancer(settings: settings).enhance(source)
            } else if let look = recipe.look {
                PhotoEnhancer().enhance(source, look: look)
            } else {
                nil
            }
        }.value
        guard !Task.isCancelled else { return }
        filtered = result.map { (recipe, $0) }
    }

    /// First zoom → fetch a bigger version once, so the photo stays sharp.
    /// Photos never returns more than the original size, so 3× screen is safe.
    private func loadSharperImage(screenSize: CGSize) {
        guard !isSharp else { return }
        isSharp = true   // set first: zoom fires many times while pinching
        let pixels = CGSize(width: screenSize.width * displayScale * 3,
                            height: screenSize.height * displayScale * 3)
        Task {
            if let sharp = await loadImage(assetID, pixels) {
                image = sharp
            }
        }
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
