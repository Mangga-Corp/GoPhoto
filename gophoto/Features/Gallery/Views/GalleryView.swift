//
//  GalleryView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  Gallery with Apple Photos layout: floating top header in ZStack (title & subtitle),
//  floating bottom capsule tab bar (Library & Collections) and floating circular search button,
//  styled with the GoPhoto design system colors.
//

import SwiftUI
import SwiftData
import Photos

// MARK: - ⚙️ PENGATURAN FOTO PLACEHOLDER SAAT GALERI KOSONG
enum EmptyGalleryConfig {
    static let topCardImage: String = "OnboardingPhoto01"
    static let leftCardImage: String = "OnboardingPhoto02"
    static let rightCardImage: String = "OnboardingPhoto03"
    static let emptyText: String = "Let’s build up your gallery with the Vacato"
}

// MARK: - Navigation Tab Model (Apple Photos Layout)
enum GalleryTab: Hashable {
    case library
    case collections
}

// MARK: - Collections Layout Model (Sesuai Menu Collections)
enum CollectionLayout: String {
    case cards
    case gridSmall
    case gridLarge
}

// MARK: - Filter Model
enum GalleryFilter: Equatable {
    case all
    case preset(UUID, String)
}

struct GalleryView: View {
    /// Owned by the presenter (GalleryScreen); @Observable, so a plain reference is enough.
    let viewModel: GalleryViewModel
    
    var onDismiss: (() -> Void)? = nil
    
    @Query(sort: \GalleryPhoto.createdAt, order: .reverse)
    private var photos: [GalleryPhoto]

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var photoZoom

    // Observe saved preferences so newly created preferences appear reactively
    @State private var preferencesViewModel = PreferencesViewModel.shared

    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var favoriteIDs: Set<String> = {
        let saved = UserDefaults.standard.stringArray(forKey: "gallery_favorite_asset_ids") ?? []
        return Set(saved)
    }()
    @State private var isDeleting = false
    @State private var isShowingDeleteConfirmation = false

    // Filter & Sort state
    @State private var activeFilter: GalleryFilter = .all
    @State private var sortAscending = false

    // Tabs & Search state (Apple Photos layout)
    @State private var currentTab: GalleryTab = .library
    @State private var isSearchActive = false
    @State private var searchText = ""
    @FocusState private var isSearchFieldFocused: Bool

    // Search History State (UserDefaults)
    @State private var recentSearches: [String] = {
        let saved = UserDefaults.standard.stringArray(forKey: "gallery_recent_searches") ?? []
        return saved.filter { $0 != "Portraits" && $0 != "Recent Photos" }
    }()

    // Collections Tab Options (Layout & Collapse)
    @State private var collectionLayout: CollectionLayout = .cards
    @State private var isCollectionsCollapsed = false

    /// Width of one grid cell in points
    @State private var cellSide: CGFloat = 78

    // MARK: - ⚙️ PENGATURAN TINGGI HEADER (NAIK / TURUN)
    // ---------------------------------------------------------------------------------
    /// Ubah nilai ini untuk menaikkan atau menurunkan posisi (Back button, Gallery title, Filter, Select):
    /// - Semakin KECIL nilainya (misal: 6, 10, 12) -> posisi header semakin NAIK ke atas.
    /// - Semakin BESAR nilainya (misal: 35, 54) -> posisi header semakin TURUN ke bawah.
    private let headerTopPadding: CGFloat = 12

    /// Tinggi kompensasi spacer agar foto paling atas tidak tertutup oleh header
    private var headerSpacerHeight: CGFloat { headerTopPadding + 72 }
    // ---------------------------------------------------------------------------------

    // 5 kolom sesuai layout Apple Photos dengan spacing 2pt
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        ZStack(alignment: .top) {
            // Background pattern (#9A69C9 20% circles + #EBDFF6 halftone dots)
            AppPatternBackground()

            if isSearchActive {
                searchOverlayView
                    .transition(.opacity)
            } else {
                // Konten Utama (Grid Foto edge-to-edge / Collections / Empty State)
                mainContent

                // Gradient halus di bagian atas agar teks judul selalu kontras & terbaca
                topGradientOverlay
                    .allowsHitTesting(false)

                // Header paling atas (ZStack) berisi tulisan Gallery & tombol aksi
                topHeaderBar

                // Floating Bar HANYA saat Mode Seleksi aktif (untuk aksi Share, Favorite, Delete)
                if isSelecting {
                    VStack {
                        Spacer()
                        selectionFloatingBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
        }
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        // Error alert untuk delete
        .alert("Couldn't Delete", isPresented: deleteErrorBinding(when: isSelecting)) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.deleteErrorMessage ?? "")
        }
        // Custom Delete Confirmation Modal
        .overlay {
            if isShowingDeleteConfirmation {
                deleteConfirmationOverlay
                    .transition(.opacity)
            }
        }
        .task {
            await viewModel.onAppear()
            syncFavoritesFromPhotoLibrary()
        }
        .task(id: photos.map(\.assetID)) {
            await viewModel.prepareThumbnails(for: photos.map(\.assetID))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.removeDeletedPhotos() }
            }
        }
        .navigationDestination(for: GalleryPhoto.self) { photo in
            PhotoPagerView(
                photos: filteredPhotos,
                startID: photo.assetID,
                loadImage: viewModel.fullImage,
                loadThumbnail: viewModel.thumbnail,
                onDelete: viewModel.delete(assetID:),
                onSaveEdit: viewModel.saveEdited
            )
            .navigationTransition(.zoom(sourceID: photo.assetID, in: photoZoom))
            .alert("Couldn't Delete", isPresented: deleteErrorBinding(when: !isSelecting)) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.deleteErrorMessage ?? "")
            }
        }
    }

    // MARK: - Main Content Switcher

    @ViewBuilder
    private var mainContent: some View {
        switch viewModel.access {
        case .notDetermined:
            VStack {
                Spacer()
                ProgressView()
                    .tint(GoPhotoDesign.primary)
                Spacer()
            }

        case .denied:
            ContentUnavailableView {
                Label("No Access to Photos", systemImage: "photo.badge.exclamationmark")
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
            } description: {
                Text("Allow Vacato to access your photos in Settings to see the photos you took.")
                    .foregroundStyle(Color(GoPhotoDesign.secondaryText))
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .tint(GoPhotoDesign.primary)
            }
            .padding(.top, 100)

        case .allowed:
            if filteredPhotos.isEmpty {
                VStack(spacing: 0) {
                    Color.clear.frame(height: headerSpacerHeight)
                    emptyStateView
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Spacer kompensasi tinggi header agar foto pertama tidak tertutup
                        Color.clear.frame(height: headerSpacerHeight)

                        // Grid 5 kolom edge-to-edge
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(filteredPhotos) { photo in
                                cell(for: photo)
                            }
                        }
                        .padding(.horizontal, 0)

                        // Spacer bawah ringan
                        Color.clear.frame(height: 30)
                    }
                }
                .scrollIndicators(.hidden)
                .onGeometryChange(for: CGFloat.self) { ($0.size.width - 8) / 5 } action: { side in
                    if side > 30 { cellSide = side }
                }
            }
        }
    }

    // MARK: - Empty State View

    @ViewBuilder
    private var emptyStateView: some View {
        switch activeFilter {
        case .all:
            emptyGalleryCardsView(
                title: nil,
                message: EmptyGalleryConfig.emptyText
            )
        case .preset(_, let name):
            emptyGalleryCardsView(
                title: "No Photos for “\(name)”",
                message: "Photos captured with this preference will appear here."
            )
        }
    }

    // MARK: - Filtered Photos Logic

    private var filteredPhotos: [GalleryPhoto] {
        var list = photos
        switch activeFilter {
        case .all:
            break
        case .preset(let id, _):
            list = list.filter { $0.presetID == id }
        }
        if sortAscending {
            list = list.sorted { $0.createdAt < $1.createdAt }
        } else {
            list = list.sorted { $0.createdAt > $1.createdAt }
        }
        return list
    }

    // MARK: - Top Gradient Overlay

    private var topGradientOverlay: some View {
        LinearGradient(
            colors: [
                Color(GoPhotoDesign.background).opacity(0.96),
                Color(GoPhotoDesign.background).opacity(0.75),
                Color(GoPhotoDesign.background).opacity(0.2),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: headerSpacerHeight + 25)
        .ignoresSafeArea()
    }

    // MARK: - Top Header Bar (ZStack paling atas)

    private var topHeaderBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                // Judul "Gallery" & status sync di sebelah kiri
                HStack(alignment: .top, spacing: 10) {
                    if let onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color(GoPhotoDesign.primaryText))
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                                )
                                .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Gallery")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color(GoPhotoDesign.primaryText))

                        // Subtitle: nama filter aktif & jumlah foto yang dihasilkan
                        HStack(spacing: 5) {
                            Image(systemName: subtitleIcon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(statusSubtitle)
                                .font(.system(size: 13, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                    }
                }

                Spacer()

                // Tombol Aksi di sebelah kanan (Filter & Select)
                HStack(spacing: 10) {
                    // Tombol Filter (Menu)
                    filterMenuButton

                    // Tombol Select / Done
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isSelecting.toggle()
                            if !isSelecting {
                                selectedIDs.removeAll()
                            }
                        }
                    } label: {
                        Text(isSelecting ? "Done" : "Select")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(GoPhotoDesign.primaryText))
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, headerTopPadding)
    }

    // MARK: - Search View Overlay (Sesuai Screenshot Referensi Apple Photos)

    private var searchOverlayView: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Judul "Search" di paling atas
                    Text("Search")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color(GoPhotoDesign.primaryText))
                        .padding(.horizontal, 16)
                        .padding(.top, headerTopPadding)

                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Section "Recents"
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Recents")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Color(GoPhotoDesign.primaryText))

                                Spacer()

                                if !recentSearches.isEmpty {
                                    HStack(spacing: 8) {
                                        Button {
                                            withAnimation {
                                                recentSearches.removeAll()
                                                UserDefaults.standard.removeObject(forKey: "gallery_recent_searches")
                                            }
                                        } label: {
                                            Text("Clear")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(GoPhotoDesign.primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(.ultraThinMaterial, in: Capsule())
                                                .overlay(
                                                    Capsule().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                                                )
                                        }

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                                            .frame(width: 28, height: 28)
                                            .background(.ultraThinMaterial, in: Circle())
                                            .overlay(
                                                Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                                            )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)

                            // Kartu-kartu Recents (horizontal scroll)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    if let firstPhoto = photos.first {
                                        searchRecentCard(
                                            title: "Recently Added",
                                            assetID: firstPhoto.assetID
                                        ) {
                                            isSearchFieldFocused = false
                                            isSearchActive = false
                                        }
                                    }

                                    if photos.count > 1 {
                                        searchRecentCard(
                                            title: "Recently Viewed",
                                            assetID: photos[min(1, photos.count - 1)].assetID
                                        ) {
                                            isSearchFieldFocused = false
                                            isSearchActive = false
                                        }
                                    }

                                    ForEach(PreferencesViewModel.shared.preferences.prefix(3)) { pref in
                                        let prefPhoto = photos.first(where: { $0.presetID == pref.id })
                                        searchRecentCard(
                                            title: pref.name,
                                            assetID: prefPhoto?.assetID ?? pref.photos.first?.sourceAssetIdentifier
                                        ) {
                                            activeFilter = .preset(pref.id, pref.name)
                                            isSearchFieldFocused = false
                                            isSearchActive = false
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Recent search chips (History pencarian sebelumnya)
                        // HANYA muncul saat klik untuk mengetik (isSearchFieldFocused == true)
                        if isSearchFieldFocused && !recentSearches.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(recentSearches, id: \.self) { query in
                                    Button {
                                        searchText = query
                                        isSearchFieldFocused = false
                                    } label: {
                                        Text(query)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Color(GoPhotoDesign.primaryText))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 10)
                                            .background(.ultraThinMaterial, in: Capsule())
                                            .overlay(
                                                Capsule().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                                            )
                                            .shadow(color: .black.opacity(0.04), radius: 4, y: 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    } else {
                        // Hasil pencarian saat user mengetik
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Results for “\(searchText)”")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                                .padding(.horizontal, 16)

                            if searchResults.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.system(size: 36))
                                        .foregroundStyle(Color(GoPhotoDesign.disabledText))
                                    Text("No matching photos found")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            } else {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(searchResults) { photo in
                                        cell(for: photo)
                                    }
                                }
                                .padding(.horizontal, 0)
                            }
                        }
                    }

                    // Spacer agar konten paling bawah tidak tertutup floating search bar
                    Color.clear.frame(height: 120)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .onTapGesture {
                isSearchFieldFocused = false
            }

            // Floating Search Bar di bagian bawah (ikut naik saat keyboard muncul)
            searchBottomFloatingBar
        }
    }

    private var searchBottomFloatingBar: some View {
        HStack(spacing: 10) {
            // Tombol kembali ke galeri di kiri
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isSearchFieldFocused = false
                    isSearchActive = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 19))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            // Bar input search di tengah
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(GoPhotoDesign.secondaryText))

                TextField("Search your library...", text: $searchText)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        saveSearchQuery(searchText)
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

            // Tombol X (tutup search) di kanan
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isSearchFieldFocused = false
                    isSearchActive = false
                    searchText = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func searchRecentCard(title: String, assetID: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(GoPhotoDesign.secondaryBackground))
                    .frame(width: 140, height: 140)

                if let assetID {
                    DialogThumbnailPreview(
                        assetID: assetID,
                        loadThumbnail: viewModel.thumbnail
                    )
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 34))
                        .foregroundStyle(Color(GoPhotoDesign.disabledText))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.65)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(10)
            }
            .frame(width: 140, height: 140)
            .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func saveSearchQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        if recentSearches.count > 6 {
            recentSearches = Array(recentSearches.prefix(6))
        }
        UserDefaults.standard.set(recentSearches, forKey: "gallery_recent_searches")
    }

    private var searchResults: [GalleryPhoto] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }
        return photos.filter { photo in
            if let presetID = photo.presetID,
               let pref = PreferencesViewModel.shared.preferences.first(where: { $0.id == presetID }) {
                if pref.name.lowercased().contains(query) { return true }
            }
            let dateStr = photo.createdAt.formatted(date: .abbreviated, time: .omitted).lowercased()
            if dateStr.contains(query) { return true }
            return false
        }
    }

    private var subtitleIcon: String {
        switch activeFilter {
        case .all:
            return "photo.stack"
        case .preset:
            return "slider.horizontal.3"
        }
    }

    private var statusSubtitle: String {
        switch activeFilter {
        case .all:
            return "All Photos (\(photos.count))"
        case .preset(_, let name):
            return "\(name) (\(filteredPhotos.count))"
        }
    }

    // MARK: - Filter Menu Button (Filter Photos & Sort Order)

    private var filterMenuButton: some View {
        Menu {
            Section("Filter Photos") {
                Button {
                    activeFilter = .all
                } label: {
                    if activeFilter == .all {
                        Label("All Photos", systemImage: "checkmark")
                    } else {
                        Text("All Photos")
                    }
                }

                ForEach(preferencesViewModel.preferences) { pref in
                    Button {
                        activeFilter = .preset(pref.id, pref.name)
                    } label: {
                        if case .preset(let id, _) = activeFilter, id == pref.id {
                            Label(pref.name, systemImage: "checkmark")
                        } else {
                            Text(pref.name)
                        }
                    }
                }
            }

            Section("Sort Order") {
                Button {
                    sortAscending = false
                } label: {
                    if !sortAscending {
                        Label("Newest First", systemImage: "checkmark")
                    } else {
                        Text("Newest First")
                    }
                }

                Button {
                    sortAscending = true
                } label: {
                    if sortAscending {
                        Label("Oldest First", systemImage: "checkmark")
                    } else {
                        Text("Oldest First")
                    }
                }
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)

                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
            }
        }
    }

    // MARK: - Floating Bottom Bar (Library & Collections Capsule + Search Circle)

    private var bottomFloatingBar: some View {
        HStack(spacing: 12) {
            // Kiri: Capsule berisikan Library & Collections Tab
            HStack(spacing: 28) {
                // Tab Library
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentTab = .library
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "photo.stack.fill")
                            .font(.system(size: 20))
                        Text("Library")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(currentTab == .library ? GoPhotoDesign.primary : Color(GoPhotoDesign.secondaryText))
                }
                .buttonStyle(.plain)

                // Tab Collections
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentTab = .collections
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "rectangle.stack.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(currentTab == .collections ? GoPhotoDesign.primary : Color(GoPhotoDesign.secondaryText))

                            // Badge merah "1"
                            Text("1")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 15, height: 15)
                                .background(Color.red, in: Circle())
                                .offset(x: 10, y: -5)
                        }

                        Text("Collections")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(currentTab == .collections ? GoPhotoDesign.primary : Color(GoPhotoDesign.secondaryText))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .frame(height: 60)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.08), radius: 16, y: 6)

            Spacer()

            // Kanan: Tombol Search lingkaran mengambang (Search button di kanan bawah)
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isSearchActive.toggle()
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Color(GoPhotoDesign.primaryText))
                    .frame(width: 60, height: 60)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(
                        Circle().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Floating Selection Bar (Saat Memilih Foto)

    private var selectionFloatingBar: some View {
        HStack(spacing: 36) {
            // Tombol Share (Native Apple Share Sheet)
            if selectedIDs.isEmpty {
                Button {
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(GoPhotoDesign.disabledText))
                }
                .disabled(true)
                .buttonStyle(.plain)
            } else {
                ShareLink(
                    items: selectedIDs.map { SharedPhoto(assetID: $0) },
                    preview: { _ in SharePreview("Photo", image: Image(systemName: "photo")) }
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(GoPhotoDesign.primaryText))
                }
                .buttonStyle(.plain)
            }

            // Tombol Favorite (Love Warna Ungu GoPhoto)
            Button {
                toggleFavoriteSelected()
            } label: {
                Image(systemName: isAllSelectedFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        selectedIDs.isEmpty
                            ? Color(GoPhotoDesign.disabledText)
                            : (isAllSelectedFavorite ? GoPhotoDesign.primary : Color(GoPhotoDesign.primaryText))
                    )
            }
            .disabled(selectedIDs.isEmpty)
            .buttonStyle(.plain)

            Button {
                if !selectedIDs.isEmpty {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isShowingDeleteConfirmation = true
                    }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selectedIDs.isEmpty ? Color(GoPhotoDesign.error).opacity(0.35) : Color(GoPhotoDesign.error))
            }
            .disabled(selectedIDs.isEmpty)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(Color(GoPhotoDesign.border), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: - Collections Content Tab

    private var collectionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Color.clear.frame(height: headerSpacerHeight)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Albums & Styles")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Color(GoPhotoDesign.primaryText))

                        Spacer()

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCollectionsCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: isCollectionsCollapsed ? "chevron.down" : "chevron.up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                        }
                    }
                    .padding(.horizontal, 16)

                    if !isCollectionsCollapsed {
                        switch collectionLayout {
                        case .cards:
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 14) {
                                    allPhotosAlbumCard(width: 140, height: 140)
                                    ForEach(PreferencesViewModel.shared.preferences) { pref in
                                        prefAlbumCard(pref: pref, width: 140, height: 140)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }

                        case .gridSmall:
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 14) {
                                allPhotosAlbumCard(width: nil, height: 105)
                                ForEach(PreferencesViewModel.shared.preferences) { pref in
                                    prefAlbumCard(pref: pref, width: nil, height: 105)
                                }
                            }
                            .padding(.horizontal, 16)

                        case .gridLarge:
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 16) {
                                allPhotosAlbumCard(width: nil, height: 155)
                                ForEach(PreferencesViewModel.shared.preferences) { pref in
                                    prefAlbumCard(pref: pref, width: nil, height: 155)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }

                Color.clear.frame(height: 90)
            }
        }
    }

    private func allPhotosAlbumCard(width: CGFloat?, height: CGFloat) -> some View {
        Button {
            activeFilter = .all
            currentTab = .library
        } label: {
            albumCard(
                title: "All Photos",
                count: photos.count,
                firstAssetID: photos.first?.assetID,
                width: width,
                height: height
            )
        }
        .buttonStyle(.plain)
    }

    private func prefAlbumCard(pref: Preference, width: CGFloat?, height: CGFloat) -> some View {
        let prefPhotos = photos.filter { $0.presetID == pref.id }
        return Button {
            activeFilter = .preset(pref.id, pref.name)
            currentTab = .library
        } label: {
            albumCard(
                title: pref.name,
                count: prefPhotos.count,
                firstAssetID: prefPhotos.first?.assetID ?? pref.photos.first?.sourceAssetIdentifier,
                width: width,
                height: height
            )
        }
        .buttonStyle(.plain)
    }

    private func albumCard(title: String, count: Int, firstAssetID: String?, width: CGFloat?, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(GoPhotoDesign.secondaryBackground))

                if let firstAssetID {
                    DialogThumbnailPreview(
                        assetID: firstAssetID,
                        loadThumbnail: viewModel.thumbnail
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(Color(GoPhotoDesign.disabledText))
                }
            }
            .frame(width: width, height: height)

            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(GoPhotoDesign.primaryText))
                .lineLimit(1)

            Text("\(count) Photos")
                .font(.system(size: 12))
                .foregroundStyle(Color(GoPhotoDesign.secondaryText))
        }
        .frame(width: width)
    }

    // MARK: - Cell View (Native Square Tile with Spacing)

    @ViewBuilder
    private func cell(for photo: GalleryPhoto) -> some View {
        let isSelected = selectedIDs.contains(photo.assetID)
        let isFavorited = favoriteIDs.contains(photo.assetID)
        let thumbnail = GalleryThumbnailView(
            assetID: photo.assetID,
            createdAt: photo.createdAt,
            loadThumbnail: viewModel.thumbnail,
            side: cellSide
        )

        if isSelecting {
            Button {
                toggleSelection(photo.assetID)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    thumbnail
                        .overlay {
                            if isSelected {
                                Rectangle()
                                    .stroke(GoPhotoDesign.primary, lineWidth: 2)
                            }
                        }

                    // Love warna ungu jika foto difavoritkan
                    if isFavorited {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GoPhotoDesign.primary)
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Checkmark indicator dengan warna brand GoPhoto di kanan bawah
                    ZStack {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 19))
                                .foregroundStyle(GoPhotoDesign.primary, .white)
                        } else {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                                .background(Circle().fill(Color.black.opacity(0.3)))
                                .frame(width: 19, height: 19)
                        }
                    }
                    .padding(4)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            NavigationLink(value: photo) {
                ZStack(alignment: .bottomTrailing) {
                    thumbnail

                    // Love warna ungu di kanan bawah saat browsing normal
                    if isFavorited {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(GoPhotoDesign.primary)
                            .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 1)
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: photo.assetID, in: photoZoom)
        }
    }

    // MARK: - Empty State (3 Foto Bertumpuk/Miring)

    private func emptyGalleryCardsView(title: String?, message: String) -> some View {
        VStack(spacing: 36) {
            ZStack {
                PlaceholderCard(imageName: EmptyGalleryConfig.topCardImage)
                    .offset(y: -44)

                PlaceholderCard(imageName: EmptyGalleryConfig.leftCardImage)
                    .rotationEffect(.degrees(-9))
                    .offset(x: -42, y: 16)

                PlaceholderCard(imageName: EmptyGalleryConfig.rightCardImage)
                    .rotationEffect(.degrees(7))
                    .offset(x: 42, y: 28)
            }
            .frame(height: 250)

            VStack(spacing: 6) {
                if let title {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(GoPhotoDesign.primaryText))
                }

                Text(message)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(GoPhotoDesign.secondaryText))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Custom Delete Confirmation Dialog

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
                    Text("Allow “Vacato” to delete\n\(selectedIDs.count) \(selectedIDs.count == 1 ? "photo" : "photos")?")
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

                    if let firstSelectedID = selectedIDs.first {
                        DialogThumbnailPreview(
                            assetID: firstSelectedID,
                            loadThumbnail: viewModel.thumbnail
                        )
                    }
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
                        Task {
                            await deleteSelected()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                isShowingDeleteConfirmation = false
                            }
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

    // MARK: - Actions

    private func toggleSelection(_ id: String) {
        withAnimation(.easeInOut(duration: 0.18)) {
            if selectedIDs.contains(id) {
                selectedIDs.remove(id)
            } else {
                selectedIDs.insert(id)
            }
        }
    }

    private var isAllSelectedFavorite: Bool {
        guard !selectedIDs.isEmpty else { return false }
        return selectedIDs.allSatisfy { favoriteIDs.contains($0) }
    }

    private func toggleFavoriteSelected() {
        guard !selectedIDs.isEmpty else { return }
        let shouldFavorite = !isAllSelectedFavorite
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if shouldFavorite {
                favoriteIDs.formUnion(selectedIDs)
            } else {
                favoriteIDs.subtract(selectedIDs)
            }
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: "gallery_favorite_asset_ids")

        // Sync status favorite ke iOS Photos library
        let targetIDs = Array(selectedIDs)
        Task {
            try? await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: targetIDs, options: nil)
                for i in 0..<assets.count {
                    let asset = assets.object(at: i)
                    let request = PHAssetChangeRequest(for: asset)
                    request.isFavorite = shouldFavorite
                }
            }
        }
    }

    private func syncFavoritesFromPhotoLibrary() {
        let allAssetIDs = photos.map(\.assetID)
        guard !allAssetIDs.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: allAssetIDs, options: nil)
        var systemFavorites = Set<String>()
        for i in 0..<assets.count {
            let asset = assets.object(at: i)
            if asset.isFavorite {
                systemFavorites.insert(asset.localIdentifier)
            }
        }
        if !systemFavorites.isEmpty {
            favoriteIDs.formUnion(systemFavorites)
            UserDefaults.standard.set(Array(favoriteIDs), forKey: "gallery_favorite_asset_ids")
        }
    }

    private func deleteSelected() async {
        isDeleting = true
        defer { isDeleting = false }

        guard await viewModel.delete(assetIDs: Array(selectedIDs)) else { return }

        withAnimation {
            favoriteIDs.subtract(selectedIDs)
            selectedIDs.removeAll()
            isSelecting = false
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: "gallery_favorite_asset_ids")
    }

    private func deleteErrorBinding(when active: Bool) -> Binding<Bool> {
        Binding(
            get: { active && viewModel.deleteErrorMessage != nil },
            set: { if !$0 { viewModel.deleteErrorMessage = nil } }
        )
    }
}

// MARK: - Helper: Placeholder Card (Empty State)
private struct PlaceholderCard: View {
    let imageName: String
    var width: CGFloat = 140
    var height: CGFloat = 190

    var body: some View {
        Group {
            if let uiImage = UIImage(named: imageName) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(GoPhotoDesign.secondaryBackground)
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Color(GoPhotoDesign.disabledText))
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 10, x: 0, y: 6)
    }
}

// MARK: - Helper: Dialog Thumbnail Preview
struct DialogThumbnailPreview: View {
    let assetID: String
    let loadThumbnail: (String, CGSize) async -> UIImage?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .tint(GoPhotoDesign.primary)
            }
        }
        .task {
            image = await loadThumbnail(assetID, CGSize(width: 400, height: 400))
        }
    }
}
