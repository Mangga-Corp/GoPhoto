import Observation
import SwiftUI

struct PhotoSessionSetupView: View {
    @State private var selection = PhotoSessionSetupSelection()
    @State private var isPresentingPicker = false
    @State private var isPresentingNamePrompt = false
    @State private var isShowingCustomPreference = false
    @State private var updateError: String?
    @State private var isConfirmingLeave = false
    @Environment(\.dismiss) private var dismiss

    private let preferences: PreferencesViewModel
    let onCreatePreference: ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void
    let onStartAnalyzing: (UUID) -> Void
    private let showsBackButton: Bool

    init(
        savedPreference: Preference? = nil,
        preferences: PreferencesViewModel = .shared,
        onCreatePreference: @escaping ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void,
        onStartAnalyzing: @escaping (UUID) -> Void,
        showsBackButton: Bool = false
    ) {
        let persistedPreference = savedPreference.flatMap { preferences.preference(id: $0.id) }
        _selection = State(initialValue: PhotoSessionSetupSelection(
            photos: persistedPreference?.photos ?? [],
            preferenceID: persistedPreference?.id
        ))
        self.preferences = preferences
        self.onCreatePreference = onCreatePreference
        self.onStartAnalyzing = onStartAnalyzing
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        GeometryReader { geometry in
            let thumbnailWidth = min(
                180,
                max(80, (geometry.size.width - GoPhotoDesign.sessionMargin * 2 - 24) / 3)
            )

            VStack(spacing: 0) {
                header
                    .padding(.top, 24)

                Spacer(minLength: 24)

                if selection.photos.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    selectedPhotos(thumbnailWidth: thumbnailWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, GoPhotoDesign.sessionMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GoPhotoDesign.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
        .toolbar(showsBackButton ? .visible : .hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(showsBackButton && hasUnsavedPhotos)
        .toolbar {
            if showsBackButton && hasUnsavedPhotos {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isConfirmingLeave = true
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Back")
                }
            }
        }
        .alert("Leave without saving?", isPresented: $isConfirmingLeave) {
            Button("Leave", role: .destructive) { dismiss() }
            Button("Stay", role: .cancel) { }
        } message: {
            Text("You have unfinished changes. If you leave now, your selected photos won't be saved.")
        }
        .navigationDestination(isPresented: $isShowingCustomPreference) {
            DefaultPreferenceSelectionView()
        }
        .onAppear(perform: reloadSavedPreference)
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.primary)
        .fullScreenCover(isPresented: $isPresentingPicker) {
            PhotoSessionPhotoPicker(
                initialPhotos: selection.photos,
                onSelection: selectedPhotosChanged,
                onFinish: { isPresentingPicker = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isPresentingNamePrompt) {
            PhotoSessionPhotoPicker(
                photosToName: selection.photos,
                onCreatePreference: { photos, name, completion in
                    onCreatePreference(photos, name) { result in
                        switch result {
                        case .success(let id):
                            selection.markPreferenceCreated(id: id, photos: photos)
                            completion(nil)
                        case .failure(let error):
                            completion(error.message)
                        }
                    }
                },
                onFinish: { isPresentingNamePrompt = false }
            )
            .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Photo Session Setup")
                .font(GoPhotoDesign.pageTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)

            Text("Choose how you'd like to create your photography preference.")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No photos yet")
                .font(GoPhotoDesign.sectionTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)

            Text("Add your favorite photos to get started.")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)

            privacyNote
                .padding(.top, 8)
        }
    }

    private var privacyNote: some View {
        Label("Your photos stay on this iPhone. Vacato analyses them here and never uploads them.",
              systemImage: "lock.fill")
            .font(GoPhotoDesign.secondaryBody)
            .foregroundStyle(GoPhotoDesign.tagText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(GoPhotoDesign.tagBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func selectedPhotos(thumbnailWidth: CGFloat) -> some View {
        VStack(spacing: 24) {
            Text("\(selection.photos.count) photos selected")
                .font(GoPhotoDesign.cardTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)

            if selection.hasSavedPreference {
                Text("Preference saved")
                    .font(GoPhotoDesign.cardTitle)
                    .foregroundStyle(GoPhotoDesign.primary)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(thumbnailWidth), spacing: 12), count: 3),
                    spacing: 12
                ) {
                    addPhotoTile(width: thumbnailWidth)
                    ForEach(selection.photos, id: \.id) { photo in
                        selectedPhoto(photo, width: thumbnailWidth)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            privacyNote
        }
        .frame(maxWidth: .infinity)
    }

    private func selectedPhoto(_ photo: PhotoItem, width: CGFloat) -> some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFill()
            .frame(width: width, height: width * 4 / 3)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if !selection.hasSavedPreference {
                    Button {
                        selection.remove(photoID: photo.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(7)
                    .accessibilityLabel("Remove photo")
                }
            }
            .accessibilityLabel("Selected photo")
    }

    private func addPhotoTile(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: openPicker) {
            shape
                .fill(GoPhotoDesign.primarySubtle)
                .overlay {
                    shape.strokeBorder(GoPhotoDesign.primaryBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.primary)
                }
                .frame(width: width, height: width * 4 / 3)
        }
        .buttonStyle(.plain)
        .disabled(isAddingDisabled)
        .opacity(isAddingDisabled ? 0.4 : 1)
        .accessibilityLabel("Add Photos")
    }

    private var isAddingDisabled: Bool {
        selection.isSavingPhotos || selection.isStartingAnalysis || (selection.hasSavedPreference && !selection.isPersistedPreferenceLoaded)
    }

    private var hasUnsavedPhotos: Bool {
        !selection.photos.isEmpty && !selection.hasSavedPreference
    }

    private var actions: some View {
        VStack(spacing: 11) {
            if selection.hasSavedPreference {
                SessionPrimaryButton(
                    title: "Start Analyzing",
                    isEnabled: selection.canStartAnalyzing && !selection.isStartingAnalysis,
                    action: startAnalyzing
                )
            } else if selection.photos.isEmpty {
                SessionPrimaryButton(title: "Add Your Photos", systemImage: "plus.circle", action: openPicker)

                Button("Create a Custom Preference") {
                    isShowingCustomPreference = true
                }
                .buttonStyle(.goPhotoText)
            } else {
                SessionPrimaryButton(
                    title: "Continue",
                    isEnabled: selection.canContinue,
                    action: { isPresentingNamePrompt = true }
                )
            }
        }
        .padding(.horizontal, GoPhotoDesign.sessionMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(GoPhotoDesign.background.ignoresSafeArea(edges: .bottom))
        .alert("Couldn't update saved photos", isPresented: Binding(
            get: { updateError != nil },
            set: { if !$0 { updateError = nil } }
        )) {
            Button("OK", role: .cancel) { updateError = nil }
        } message: {
            Text(updateError ?? "")
        }
    }

    private func openPicker() {
        guard !selection.isSavingPhotos, !selection.isStartingAnalysis else { return }
        isPresentingPicker = true
    }

    private func startAnalyzing() {
        guard let id = selection.preferenceID,
              selection.canStartAnalyzing,
              !selection.isStartingAnalysis,
              preferences.preference(id: id) != nil else {
            updateError = "The saved preference is unavailable. Return to Preference Selection and try again."
            return
        }
        selection.isStartingAnalysis = true
        preferences.prepareForReanalysis(id: id) { result in
            switch result {
            case .success:
                onStartAnalyzing(id)
            case .failure(let error):
                selection.isStartingAnalysis = false
                updateError = error.message
            }
        }
    }

    private func reloadSavedPreference() {
        guard let id = selection.preferenceID else { return }
        selection.isPersistedPreferenceLoaded = false
        preferences.loadPersistedPreference(id: id) { result in
            switch result {
            case .success(let preference):
                guard preference.id == id else {
                    selection.isPersistedPreferenceLoaded = false
                    updateError = "The saved preference could not be verified."
                    return
                }
                selection.reloadSavedPreference(preference)
            case .failure:
                selection.isPersistedPreferenceLoaded = false
                updateError = "The saved preference couldn't be loaded. Please return and try again."
            }
        }
    }

    private func selectedPhotosChanged(_ photos: [PhotoItem]) {
        guard let id = selection.preferenceID else {
            selection.replace(with: photos)
            return
        }
        guard !selection.isSavingPhotos else { return }
        selection.isSavingPhotos = true
        preferences.addPhotosPersisted(photos, to: id) { result in
            selection.isSavingPhotos = false
            switch result {
            case .success(let preference):
                selection.reloadSavedPreference(preference)
            case .failure(let error):
                updateError = error.message
            }
        }
    }
}

@Observable
final class PhotoSessionSetupSelection {
    private(set) var photos: [PhotoItem]
    private(set) var preferenceID: UUID?
    var isPersistedPreferenceLoaded: Bool
    var isSavingPhotos = false
    var isStartingAnalysis = false

    var hasSavedPreference: Bool { preferenceID != nil }

    var canContinue: Bool {
        !hasSavedPreference && photos.count >= ChoosePhotosViewModel.minPhotos
    }

    var canStartAnalyzing: Bool {
        hasSavedPreference && isPersistedPreferenceLoaded && !isSavingPhotos && !photos.isEmpty
    }

    init(photos: [PhotoItem] = [], preferenceID: UUID? = nil) {
        self.photos = photos
        self.preferenceID = preferenceID
        isPersistedPreferenceLoaded = preferenceID == nil
    }

    func replace(with newPhotos: [PhotoItem]) {
        guard !hasSavedPreference else { return }
        photos = []
        append(newPhotos)
    }

    func remove(photoID: UUID) {
        guard !hasSavedPreference else { return }
        photos.removeAll { $0.id == photoID }
    }

    func markPreferenceCreated(id: UUID, photos: [PhotoItem]) {
        preferenceID = id
        self.photos = photos
        isPersistedPreferenceLoaded = true
    }

    func reloadSavedPreference(_ preference: Preference) {
        guard preferenceID == preference.id else { return }
        photos = preference.photos
        isPersistedPreferenceLoaded = true
    }

    private func append(_ newPhotos: [PhotoItem]) {
        var assetIdentifiers = Set<String>()
        var itemIdentifiers = Set<UUID>()
        for photo in newPhotos {
            guard photos.count < ChoosePhotosViewModel.maxPhotos else { return }
            guard itemIdentifiers.insert(photo.id).inserted else { continue }
            if let sourceAssetIdentifier = photo.sourceAssetIdentifier {
                guard assetIdentifiers.insert(sourceAssetIdentifier).inserted else { continue }
            }
            photos.append(photo)
        }
    }
}
