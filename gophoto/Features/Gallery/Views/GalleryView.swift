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
    
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isDeleting = false
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    var body: some View {
        content
            .navigationTitle(isSelecting ? selectionTitle: "Gallery")
            .toolbar {
                if viewModel.access == .allowed && !photos.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelecting ? "Cancel" : "Select") {
                            isSelecting.toggle()
                            selectedIDs.removeAll()   // start fresh every time
                        }
                    }
                }
                if isSelecting {
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await deleteSelected() }
                        }
                        .disabled(selectedIDs.isEmpty || isDeleting)
                    }
                }
            }
        // Error alert for deleting from the grid (select mode)
            .alert("Couldn't Delete", isPresented: deleteErrorBinding(when: isSelecting)) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.deleteErrorMessage ?? "")
            }
        
            .task { await viewModel.onAppear() }
            .onChange(of: scenePhase,){_, phase in if phase == .active {viewModel.removeDeletedPhotos()
            }
            }
            .navigationDestination(for: GalleryPhoto.self) { photo in
                PhotoPagerView(photos: photos,
                               startID: photo.assetID,
                               loadImage: viewModel.fullImage,
                               loadThumbnail: viewModel.thumbnail,
                               onDelete: viewModel.delete(assetID:))
                .navigationTransition(.zoom(sourceID: photo.assetID, in: photoZoom))
                // Alert lives on the pager (the screen on top), not on the grid
                .alert("Couldn't Delete", isPresented: deleteErrorBinding(when: !isSelecting)) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(viewModel.deleteErrorMessage ?? "")
                }
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
                            cell(for: photo)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func cell(for photo: GalleryPhoto) -> some View {
        let thumbnail = GalleryThumbnailView(
            assetID: photo.assetID,
            createdAt: photo.createdAt,
            loadThumbnail: viewModel.thumbnail
        )
        
        if isSelecting {
            let isSelected = selectedIDs.contains(photo.assetID)
            Button {
                toggleSelection(photo.assetID)
            } label: {
                thumbnail
                // Light wash + checkmark, like the Photos app
                    .overlay { if isSelected { Color.white.opacity(0.25) } }
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .tint)
                                .padding(4)
                        }
                    }
            }
            .buttonStyle(.plain)
            // VoiceOver reads "Selected"
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            NavigationLink(value: photo) { thumbnail }
                .buttonStyle(.plain)
                .matchedTransitionSource(id: photo.assetID, in: photoZoom)
        }
    }
    
    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    private var selectionTitle: String {
        switch selectedIDs.count {
        case 0:  "Select Items"
        case 1:  "1 Photo Selected"
        default: "\(selectedIDs.count) Photos Selected"
        }
    }
    
    /// Deletes every ticked photo (one system alert), then leaves select mode.
    private func deleteSelected() async {
        isDeleting = true
        defer { isDeleting = false }
        
        // false = user tapped "Don't Allow" or it failed → keep the selection
        guard await viewModel.delete(assetIDs: Array(selectedIDs)) else { return }
        
        selectedIDs.removeAll()
        isSelecting = false
    }
    
    private func deleteErrorBinding(when active: Bool) -> Binding<Bool> {
        Binding(
            get: { active && viewModel.deleteErrorMessage != nil },
            set: { if !$0 { viewModel.deleteErrorMessage = nil } }
        )
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
