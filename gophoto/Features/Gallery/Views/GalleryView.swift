//
//  GalleryView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  grid of photos taken in the app
//  Shows one of 4 screens: loading / no access / no photos yet / grid.
//

import SwiftUI
import SwiftData

struct GalleryView: View {
    @State var viewModel: GalleryViewModel

    @Query(sort: \GalleryPhoto.createdAt, order: .reverse)
    private var photos: [GalleryPhoto]

    /// Open setting page for this app
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var photoZoom
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        content
            .navigationTitle("Gallery")
            .task { await viewModel.onAppear() }
            .onChange(of: scenePhase,){_, phase in if phase == .active {viewModel.removeDeletedPhotos()
                }
            }
            .navigationDestination(for: GalleryPhoto.self){photo in
                PhotoPagerView(photos: photos,
                               startID: photo.assetID,
                               loadImage: viewModel.fullImage,
                               loadThumbnail: viewModel.thumbnail)
                .navigationTransition(.zoom(sourceID: photo.assetID, in: photoZoom))
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.access {

        case .notDetermined:
            ProgressView()

        // User said no (or access is restricted): explain + offer a way to fix it
        case .denied:
            ContentUnavailableView {
                Label("No Access to Photos", systemImage: "photo.badge.exclamationmark")
            } description: {
                Text("Allow GoPhoto to access your photos in Settings to see the photos you took.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }

        // Allowed (full or limited)
        case .allowed:
            if photos.isEmpty {
                ContentUnavailableView(
                    "No Photos Yet",
                    systemImage: "photo.on.rectangle",
                    description: Text("Photos you take with GoPhoto appear here.")
                )
            } else {
                // LazyVGrid only builds cells that are on screen → cheap even with many photos
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(photos) { photo in
                            NavigationLink(value: photo){
                                GalleryThumbnailView(
                                    assetID: photo.assetID,
                                    createdAt: photo.createdAt,
                                    loadThumbnail: viewModel.thumbnail
                                )
                            }.buttonStyle(.plain)
                                .matchedTransitionSource(id: photo.assetID, in: photoZoom)
                        }
                    }
                }
            }
        }
    }
}


#if DEBUG
extension ModelContainer {
    static func galleryPreview(count: Int) -> ModelContainer {
        let container = try! ModelContainer(
            for: GalleryPhoto.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for i in 0..<count {
            container.mainContext.insert(
                GalleryPhoto(assetID: "asset-\(i)", createdAt: .now.addingTimeInterval(Double(-i) * 60))
            )
        }
        return container
    }
}

#Preview("Photos") {
    NavigationStack {
        GalleryView(viewModel: GalleryViewModel(
            authorization: MockPhotoAuthorization(),
            imageLoader: MockImageLoader()
        ))
    }
    .modelContainer(.galleryPreview(count: 14))
}

#Preview("Deleted photo") {
    NavigationStack {
        GalleryView(viewModel: GalleryViewModel(
            authorization: MockPhotoAuthorization(),
            imageLoader: {
                let loader = MockImageLoader()
                loader.missingIDs = ["asset-1"]
                return loader
            }()
        ))
    }
    .modelContainer(.galleryPreview(count: 6))
}

#Preview("Empty") {
    NavigationStack {
        GalleryView(viewModel: GalleryViewModel(
            authorization: MockPhotoAuthorization(),
            imageLoader: MockImageLoader()
        ))
    }
    .modelContainer(.galleryPreview(count: 0))
}

#Preview("Denied") {
    NavigationStack {
        GalleryView(viewModel: GalleryViewModel(
            authorization: MockPhotoAuthorization(access: .denied),
            imageLoader: MockImageLoader()
        ))
    }
    .modelContainer(.galleryPreview(count: 0))
}
#endif // DEBUG
