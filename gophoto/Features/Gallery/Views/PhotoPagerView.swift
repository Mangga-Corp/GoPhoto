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
    /// (assetID, presetID, settings) → error message, or nil once the edited copy is saved
    let onSaveEdit: (String, UUID?, PhotoEnhancer.Settings) async -> String?
    /// assetID of the image currently on screen
    @State private var currentID: String
    @State private var isDeleting = false
    /// AI Enhanced look previewed on the current photo; nil = photo as it is. Reset on every photo.
    @State private var selectedLook: EnhancedLook?
    /// Manual sliders for the current photo: the live values, and the AI Enhance values they started from
    @State private var adjustments: PhotoEnhancer.Settings?
    @State private var baseline: PhotoEnhancer.Settings?
    @State private var isSavingEdit = false
    @State private var editMessage: String?
    @Environment(\.dismiss) private var dismiss

    /// - Parameter startID: assetID of the photo that was tapped in the grid
    init(photos: [GalleryPhoto],
         startID: String,
         loadImage: @escaping (String, CGSize) async -> UIImage?,
    loadThumbnail: @escaping (String, CGSize) async -> UIImage?,
         onDelete: @escaping (String) async -> Bool,
         onSaveEdit: @escaping (String, UUID?, PhotoEnhancer.Settings) async -> String?) {
        self.photos = photos
        self.loadImage = loadImage
        self.loadThumbnail = loadThumbnail
        self.onDelete = onDelete
        self.onSaveEdit = onSaveEdit
        _currentID = State(initialValue: startID)
    }

    var body: some View {
        TabView(selection: $currentID) {
            ForEach(photos) { photo in
                FullPhotoView(assetID: photo.assetID,
                              createdAt: photo.createdAt,
                              loadImage: loadImage,
                              look: photo.assetID == currentID ? selectedLook : nil,
                              adjustments: photo.assetID == currentID ? adjustments : nil)
                    .tag(photo.assetID)          // links the page to currentID
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))   // swipe pages, no dots (like Photos)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // With a look selected the share sheet gets the filtered photo; it has Save Image.
                if adjustments != nil {
                    EmptyView()   // share after saving: the edit is a normal photo then
                } else if let selectedLook {
                    ShareLink(item: FilteredPhoto(assetID: currentID, look: selectedLook),
                              preview: SharePreview("Photo (\(selectedLook.title))",
                                                    image: Image(systemName: "photo")))
                } else {
                    ShareLink(item: SharedPhoto(assetID: currentID),
                              preview: SharePreview("Photo", image: Image(systemName: "photo")))
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Adjust", systemImage: "slider.horizontal.3") {
                    Task { await startEditing() }
                }.disabled(adjustments != nil || isDeleting)
            }
            ToolbarItem(placement: .bottomBar){
                Button("Delete", systemImage: "trash", role: .destructive){
                    Task{await deleteCurrent()}
                }.disabled(isDeleting || adjustments != nil)
            }
        }
        .safeAreaInset(edge: .bottom){
            VStack(spacing: 0) {
                if let binding = Binding($adjustments) {
                    AdjustPanelView(settings: binding,
                                    baseline: baseline,
                                    isSaving: isSavingEdit,
                                    onCancel: stopEditing,
                                    onSave: { Task { await saveEdit() } })
                } else {
                    LookPickerView(assetID: currentID,
                                   selection: $selectedLook,
                                   loadThumbnail: loadThumbnail)
                    PhotoStripView(photos: photos,
                                   currentID: $currentID,
                                   loadThumbnail: loadThumbnail,)
                }
            }
            .background(.bar)
        }
        .onChange(of: currentID) {
            selectedLook = nil
            stopEditing()
        }
        .alert(editMessage ?? "", isPresented: Binding(get: { editMessage != nil },
                                                       set: { if !$0 { editMessage = nil } })) {
            Button("OK", role: .cancel) { }
        }
    }

    /// Opens the sliders at the AI Enhance values of the current photo (in the selected look).
    private func startEditing() async {
        let id = currentID
        let look = selectedLook
        isSavingEdit = false
        baseline = nil
        // Screen-sized is enough to measure the photo; the full-resolution save reuses these values
        guard let image = await loadImage(id, CGSize(width: 1024, height: 1024)) else { return }
        let measured = await Task.detached(priority: .userInitiated) {
            PhotoEnhancer().baselineSettings(for: image, look: look)
        }.value
        guard id == currentID, let measured else { return }
        baseline = measured
        adjustments = measured
    }

    private func stopEditing() {
        adjustments = nil
        baseline = nil
        isSavingEdit = false
    }

    private func saveEdit() async {
        guard let settings = adjustments else { return }
        let id = currentID
        let presetID = photos.first(where: { $0.assetID == id })?.presetID
        isSavingEdit = true
        let error = await onSaveEdit(id, presetID, settings)
        isSavingEdit = false
        if let error {
            editMessage = error
        } else {
            stopEditing()
            editMessage = "Saved to your gallery as a new photo. The original is unchanged."
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
                       onDelete: { _ in true },
                       onSaveEdit: { _, _, _ in nil })
    }
}
#endif // DEBUG
