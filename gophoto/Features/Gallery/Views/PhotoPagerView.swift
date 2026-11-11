//
//  PhotoPagerView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 14/10/26.
//
//  Full-screen photo viewer matching Figma layout with top circular buttons,
//  filmstrip dot indicator, bottom controls (Info, Edit pill, ShareLink),
//  and custom delete confirmation modal.
//

import SwiftUI
import Photos

struct PhotoPagerView: View {
    let photos: [GalleryPhoto]
    let loadImage: (String, CGSize) async -> UIImage?
    let loadThumbnail: (String, CGSize) async -> UIImage?
    let onDelete: (String) async -> Bool
    /// (assetID, presetID, settings) → error message, or nil once the edited copy is saved
    let onSaveEdit: (String, UUID?, PhotoEnhancer.Settings) async -> String?

    @State private var currentID: String
    @State private var isDeleting = false
    @State private var isEditing = false
    @State private var savedMessage: String?
    @State private var isShowingDeleteConfirmation = false

    @State private var favoriteIDs: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "gallery_favorite_asset_ids") ?? []
        return Set(saved)
    }()

    @Environment(\.dismiss) private var dismiss

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

    private var isCurrentFavorited: Bool {
        favoriteIDs.contains(currentID)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Background pattern (#9A69C9 20% circles + #EBDFF6 halftone dots)
            AppPatternBackground()

            // Main Content: Photo Pager + Filmstrip + Bottom Controls
            VStack(spacing: 0) {
                // Top spacer agar foto tidak tertutup tombol header
                Color.clear.frame(height: 56)

                // Swipeable Photo Pager
                TabView(selection: $currentID) {
                    ForEach(photos) { photo in
                        ZStack(alignment: .bottomTrailing) {
                            FullPhotoView(
                                assetID: photo.assetID,
                                createdAt: photo.createdAt,
                                loadImage: loadImage
                            )

                            // Love ungu jika foto ini difavoritkan
                            if favoriteIDs.contains(photo.assetID) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(Color(hex: 0x9A69C9))
                                    .frame(width: 42, height: 42)
                                    .background(.ultraThinMaterial, in: Circle())
                                    .overlay(
                                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                                    )
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                                    .padding(.trailing, 20)
                                    .padding(.bottom, 14)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .tag(photo.assetID)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bagian Bawah: Filmstrip foto & tombol aksi (Info, Edit, Share)
                VStack(spacing: 16) {
                    PhotoStripView(
                        photos: photos,
                        currentID: $currentID,
                        loadThumbnail: loadThumbnail
                    )

                    bottomControls
                }
                .padding(.bottom, 12)
            }

            // Top Header Bar: Back & Delete (dan favorite indicator)
            topHeaderBar

            // Custom Delete Confirmation Modal (Sesuai Gambar 2)
            if isShowingDeleteConfirmation {
                deleteConfirmationOverlay
                    .transition(.opacity)
                    .zIndex(20)
            }
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $isEditing) {
            editor
        }
        .alert(savedMessage ?? "", isPresented: Binding(get: { savedMessage != nil },
                                                        set: { if !$0 { savedMessage = nil } })) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - Top Header Bar (Sesuai Gambar 1)

    private var topHeaderBar: some View {
        HStack {
            // Tombol Back (Kiri)
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 10) {
                // Tombol Love Ungu jika foto difavoritkan
                if isCurrentFavorited {
                    Button {
                        toggleFavoriteCurrent()
                    } label: {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color(hex: 0x9A69C9))
                            .frame(width: 44, height: 44)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                // Tombol Delete (Kanan)
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isShowingDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(GoPhotoDesign.primaryText))
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                        )
                        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Bottom Controls: Info, Edit, Share (Sesuai Gambar 1)

    private var bottomControls: some View {
        HStack(spacing: 20) {
            // 1. Info Button (Tetap ada, tanpa navigasi)
            Button {
                // No-op as requested
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            // 2. Edit Button (Purple Pill Button menggantikan ikon pen)
            Button {
                isEditing = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Edit")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 48)
                .background(Color(hex: 0x9A69C9), in: Capsule())
                .shadow(color: Color(hex: 0x9A69C9).opacity(0.35), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            // 3. Share Button (Native Apple Share Sheet)
            ShareLink(
                item: SharedPhoto(assetID: currentID),
                preview: SharePreview("Photo", image: Image(systemName: "photo"))
            ) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Custom Delete Confirmation Modal (Sesuai Gambar 2)

    private var deleteConfirmationOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isShowingDeleteConfirmation = false
                    }
                }

            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Allow “Pico” to delete\n1 photo?")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color(GoPhotoDesign.primaryText))
                        .multilineTextAlignment(.center)

                    Text("These photos will also be deleted from an album.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 10)
                .padding(.horizontal, 16)

                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(GoPhotoDesign.secondaryBackground))

                    DialogThumbnailPreview(
                        assetID: currentID,
                        loadThumbnail: loadThumbnail
                    )
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 8)

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isShowingDeleteConfirmation = false
                        }
                    } label: {
                        Text("Don’t Allow")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(GoPhotoDesign.primaryText))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isShowingDeleteConfirmation = false
                        }
                        Task {
                            await deleteCurrent()
                        }
                    } label: {
                        Text("Delete")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(GoPhotoDesign.error), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            )
            .padding(.horizontal, 32)
        }
    }

    private var editor: some View {
        let id = currentID
        let photo = photos.first(where: { $0.assetID == id })
        return PhotoEditorView(
            assetID: id,
            createdAt: photo?.createdAt ?? .now,
            loadImage: loadImage,
            loadThumbnail: loadThumbnail,
            onSave: { settings in await onSaveEdit(id, photo?.presetID, settings) },
            onSaved: { savedMessage = "Saved to your gallery as a new photo. The original is unchanged." }
        )
    }

    private func toggleFavoriteCurrent() {
        let shouldFavorite = !isCurrentFavorited
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if shouldFavorite {
                favoriteIDs.insert(currentID)
            } else {
                favoriteIDs.remove(currentID)
            }
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: "gallery_favorite_asset_ids")

        let targetID = currentID
        Task {
            try? await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [targetID], options: nil)
                if let asset = assets.firstObject {
                    let request = PHAssetChangeRequest(for: asset)
                    request.isFavorite = shouldFavorite
                }
            }
        }
    }

    private func deleteCurrent() async {
        isDeleting = true
        defer { isDeleting = false }

        let deletingID = currentID
        let nextID = neighbor(of: deletingID)

        guard await onDelete(deletingID) else { return }

        favoriteIDs.remove(deletingID)
        UserDefaults.standard.set(Array(favoriteIDs), forKey: "gallery_favorite_asset_ids")

        if let nextID {
            withAnimation { currentID = nextID }
        } else {
            dismiss()
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
