import Observation
import SwiftUI

struct PhotoSessionSetupView: View {
    @State private var selection = PhotoSessionSetupSelection()
    @State private var isPresentingPicker = false
    @State private var isPresentingNamePrompt = false
    @State private var isShowingCustomPreference = false
    @State private var updateError: String?

    private let preferences: PreferencesViewModel
    let onCreatePreference: ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void
    let onStartAnalyzing: (UUID) -> Void

    init(
        savedPreference: Preference? = nil,
        preferences: PreferencesViewModel = .shared,
        onCreatePreference: @escaping ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void,
        onStartAnalyzing: @escaping (UUID) -> Void
    ) {
        let persistedPreference = savedPreference.flatMap { preferences.preference(id: $0.id) }
        _selection = State(initialValue: PhotoSessionSetupSelection(
            photos: persistedPreference?.photos ?? [],
            preferenceID: persistedPreference?.id
        ))
        self.preferences = preferences
        self.onCreatePreference = onCreatePreference
        self.onStartAnalyzing = onStartAnalyzing
    }

    var body: some View {
        NavigationStack {
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
                .background(GoPhotoDesign.sessionBackground)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actions
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingCustomPreference) {
                CustomPreferenceBuilderPlaceholderView()
            }
            .onAppear(perform: reloadSavedPreference)
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.sessionAccent)
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
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)

            Text("Choose how you'd like to create your photography preference.")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No photos yet")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(GoPhotoDesign.primaryText)

            Text("Add your favorite photos to get started.")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private func selectedPhotos(thumbnailWidth: CGFloat) -> some View {
        VStack(spacing: 24) {
            Text("\(selection.photos.count) photos selected")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(GoPhotoDesign.primaryText)

            if selection.hasSavedPreference {
                Text("Preference saved")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GoPhotoDesign.sessionAccent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(selection.photos, id: \.id) { photo in
                        selectedPhoto(photo, width: thumbnailWidth)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(height: thumbnailWidth * 4 / 3)
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

    private var actions: some View {
        VStack(spacing: 11) {
            if selection.hasSavedPreference {
                SessionPrimaryButton(
                    title: "Start Analyzing",
                    isEnabled: selection.canStartAnalyzing && !selection.isStartingAnalysis,
                    action: startAnalyzing
                )

                Button("Add New Photos", action: openPicker)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(GoPhotoDesign.sessionAccent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 40)
                    .disabled(selection.isSavingPhotos || selection.isStartingAnalysis
                        || !selection.isPersistedPreferenceLoaded)
            } else if selection.photos.isEmpty {
                SessionPrimaryButton(title: "Add Your Photos", systemImage: "plus", action: openPicker)

                Button("Create a Custom Preference") {
                    isShowingCustomPreference = true
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(GoPhotoDesign.sessionAccent)
                .buttonStyle(.plain)
                .frame(minHeight: 40)
            } else {
                SessionPrimaryButton(
                    title: "Continue",
                    isEnabled: selection.canContinue,
                    action: { isPresentingNamePrompt = true }
                )

                Button("Add More Photos", action: openPicker)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(GoPhotoDesign.sessionAccent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 40)
            }

            Label("Private on your iPhone.", systemImage: "lock.fill")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .padding(.top, 4)
        }
        .padding(.horizontal, GoPhotoDesign.sessionMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(GoPhotoDesign.sessionBackground.ignoresSafeArea(edges: .bottom))
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

private struct CustomPreferenceBuilderPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Custom Preference Builder")
                .font(.title2.weight(.semibold))
                .foregroundStyle(GoPhotoDesign.primaryText)

            Text("This builder is a placeholder for a future phase.")
                .font(.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(GoPhotoDesign.sessionMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoPhotoDesign.sessionBackground)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}
