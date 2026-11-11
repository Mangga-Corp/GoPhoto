import Observation
import SwiftUI

struct PhotoSessionSetupView: View {
    @State private var selection = PhotoSessionSetupSelection()
    @State private var isPresentingPicker = false
    /// The custom preference flow while it is open (a new one each time it opens).
    @State private var customPreferenceFlow: CustomPreferenceFlowModel?
    @State private var updateError: String?
    @State private var isConfirmingLeave = false
    @State private var isSelecting = false
    @State private var selectedPhotoIDs: Set<UUID> = []
    @State private var isConfirmingDeletePhotos = false
    @State private var isShowingNameModal = false
    @State private var collectionName = ""
    @State private var hasAutoOpenedPicker = false
    @Environment(\.dismiss) private var dismiss

    private let preferences: PreferencesViewModel
    let onCreatePreference: ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void
    let onStartAnalyzing: (UUID) -> Void
    /// A custom preference (placement + angle) was saved; the opener shows the preference list.
    let onCustomPreferenceCreated: (UUID) -> Void
    private let showsBackButton: Bool

    init(
        savedPreference: Preference? = nil,
        preferences: PreferencesViewModel = .shared,
        onCreatePreference: @escaping ([PhotoItem], String, @escaping (Result<UUID, PreferenceNameError>) -> Void) -> Void,
        onStartAnalyzing: @escaping (UUID) -> Void,
        onCustomPreferenceCreated: @escaping (UUID) -> Void,
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
        self.onCustomPreferenceCreated = onCustomPreferenceCreated
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        GeometryReader { geometry in
            let thumbnailWidth = min(
                180,
                max(80, (geometry.size.width - GoPhotoDesign.sessionMargin * 2 - 24) / 3)
            )

            ZStack {
                VStack(spacing: 0) {
                    if selection.photos.isEmpty {
                        headerEmpty
                            .padding(.top, 24)
                        Spacer(minLength: 24)
                        emptyState
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Spacer(minLength: 24)
                    } else {
                        // Header as in Image 2
                        headerWithPhotos
                            .padding(.top, 16)
                            .padding(.bottom, 14)

                        selectedPhotos(thumbnailWidth: thumbnailWidth)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, GoPhotoDesign.sessionMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Name modal overlay as in Image 2 (iPhone 17 - 1)
                if isShowingNameModal {
                    nameCollectionModal
                }
            }
        }
        .appPatternBackground()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomActions
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Leave without saving?", isPresented: $isConfirmingLeave) {
            Button("Leave", role: .destructive) { dismiss() }
            Button("Stay", role: .cancel) { }
        } message: {
            Text("You have unfinished changes. If you leave now, your selected photos won't be saved.")
        }
        .navigationDestination(isPresented: isShowingCustomPreference) {
            if let customPreferenceFlow {
                SubjectPlacementSelectionView(model: customPreferenceFlow)
            }
        }
        .onAppear {
            reloadSavedPreference()
            // If user enters with no photos, automatically present the picker
            if selection.photos.isEmpty && !hasAutoOpenedPicker {
                hasAutoOpenedPicker = true
                isPresentingPicker = true
            }
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.primary)
        .fullScreenCover(isPresented: $isPresentingPicker) {
            PhotoSessionPhotoPicker(
                initialPhotos: selection.photos,
                canRemove: !selection.hasSavedPreference,
                onSelection: selectedPhotosChanged,
                onFinish: { isPresentingPicker = false }
            )
            .ignoresSafeArea()
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { updateError != nil },
            set: { if !$0 { updateError = nil } }
        )) {
            Button("OK", role: .cancel) { updateError = nil }
        } message: {
            Text(updateError ?? "")
        }
        .alert("Re-analyze the AI preferences", isPresented: $isConfirmingDeletePhotos) {
            Button("Cancel", role: .destructive) { }
            Button("Yes") {
                withAnimation {
                    selection.removePhotos(withIDs: selectedPhotoIDs)
                    selectedPhotoIDs.removeAll()
                    isSelecting = false
                }
            }
        } message: {
            Text("By Delete those picture it will redefined the ai model, are you sure ?")
        }
    }

    // MARK: - Header (Image 2 style)

    private var headerWithPhotos: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                // Back button
                Button {
                    if hasUnsavedPhotos {
                        isConfirmingLeave = true
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)

                // Title and Subtitle
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Preferences")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                    Text("\(selection.photos.count)/20")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                }
                .padding(.leading, 8)

                Spacer()

                // Select / Cancel button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelecting.toggle()
                        selectedPhotoIDs.removeAll()
                    }
                } label: {
                    Text(isSelecting ? "Cancel" : "Select")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.white, in: Capsule())
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }

            privacyNote
        }
    }

    private var headerEmpty: some View {
        VStack(spacing: 10) {
            Text("Photo Session Setup")
                .font(GoPhotoDesign.pageTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)

            privacyNote
        }
        .frame(maxWidth: .infinity)
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GoPhotoDesign.primary)

            Text("Your photos stay on this iPhone. They're analyzed on your device and never uploaded.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(GoPhotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoPhotoDesign.tagBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(GoPhotoDesign.primaryBorder.opacity(0.3), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No photos yet")
                .font(GoPhotoDesign.sectionTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)

            Text("Add at least \(ChoosePhotosViewModel.minPhotos) of your favorite photos to get started.")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Selected Photos Grid (3 Columns, 1st item = "+ Add photos" tile)

    private func selectedPhotos(thumbnailWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(thumbnailWidth), spacing: 10), count: 3),
                spacing: 10
            ) {
                addPhotoTile(width: thumbnailWidth)
                ForEach(selection.photos, id: \.id) { photo in
                    photoCell(photo, width: thumbnailWidth)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 100) // Padding for floating bottom button
            .frame(maxWidth: .infinity)
        }
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
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(GoPhotoDesign.primary)
                        Text("Add photos")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GoPhotoDesign.primary)
                    }
                }
                .frame(width: width, height: width * 4 / 3)
        }
        .buttonStyle(.plain)
        .disabled(isAddingDisabled || isSelecting)
        .opacity(isSelecting ? 0.3 : 1.0)
        .accessibilityLabel("Add Photos")
    }

    private func photoCell(_ photo: PhotoItem, width: CGFloat) -> some View {
        let isChecked = selectedPhotoIDs.contains(photo.id)
        return Button {
            if isSelecting {
                if isChecked {
                    selectedPhotoIDs.remove(photo.id)
                } else {
                    selectedPhotoIDs.insert(photo.id)
                }
            }
        } label: {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: width * 4 / 3)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        ZStack {
                            Circle()
                                .fill(isChecked ? GoPhotoDesign.primary : Color.black.opacity(0.3))
                                .frame(width: 24, height: 24)
                            if isChecked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 1.5)
                                    .frame(width: 24, height: 24)
                            }
                        }
                        .padding(6)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom Actions (Floating purple pill button)

    private var bottomActions: some View {
        VStack(spacing: 0) {
            if isSelecting {
                // Delete selected button when in select mode
                Button {
                    isConfirmingDeletePhotos = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete \(selectedPhotoIDs.count) Photos")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(selectedPhotoIDs.isEmpty ? Color.gray : GoPhotoDesign.error, in: Capsule())
                }
                .disabled(selectedPhotoIDs.isEmpty)
                .padding(.horizontal, GoPhotoDesign.sessionMargin)
                .padding(.bottom, 12)
            } else if !selection.photos.isEmpty {
                // "Analyze X photos" Floating purple button as in Image 2
                Button {
                    isShowingNameModal = true
                } label: {
                    Text("Analyze \(selection.photos.count) photos")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            selection.photos.count >= ChoosePhotosViewModel.minPhotos
                                ? GoPhotoDesign.primary
                                : GoPhotoDesign.primary.opacity(0.5),
                            in: Capsule()
                        )
                        .shadow(color: GoPhotoDesign.primary.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(selection.photos.count < ChoosePhotosViewModel.minPhotos)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            } else {
                SessionPrimaryButton(title: "Add Your Photos", systemImage: "plus.circle", action: openPicker)
                    .padding(.horizontal, GoPhotoDesign.sessionMargin)
                    .padding(.bottom, 8)

                Button("Create a Custom Preference", action: openCustomPreference)
                    .buttonStyle(.goPhotoText)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - Custom Naming Modal as in Image 2 (iPhone 17 - 1)

    private var nameCollectionModal: some View {
        ZStack {
            // Blurred backdrop
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture {
                    isShowingNameModal = false
                }

            // Card
            VStack(alignment: .leading, spacing: 14) {
                Text("What this collection going to be\n?")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(GoPhotoDesign.primaryText)
                    .lineLimit(2)

                Text("“purpose is to know if you are going to take picture based on vacation (beach/OOTD/big statue/city/night life)”")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                // Input box
                HStack {
                    TextField("....", text: $collectionName)
                        .font(.system(size: 15))
                        .autocorrectionDisabled()

                    if !collectionName.isEmpty {
                        Button {
                            collectionName = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(GoPhotoDesign.secondaryText)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Action buttons: Cancel and Save
                HStack(spacing: 12) {
                    Button {
                        isShowingNameModal = false
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GoPhotoDesign.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                    }

                    Button {
                        let trimmed = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        isShowingNameModal = false
                        saveAndAnalyze(name: trimmed)
                    } label: {
                        Text("Save")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? GoPhotoDesign.primary.opacity(0.4)
                                    : GoPhotoDesign.primary,
                                in: Capsule()
                            )
                    }
                    .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 6)
            }
            .padding(22)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
    }

    private var isShowingCustomPreference: Binding<Bool> {
        Binding(get: { customPreferenceFlow != nil },
                set: { if !$0 { customPreferenceFlow = nil } })
    }

    private func openCustomPreference() {
        customPreferenceFlow = CustomPreferenceFlowModel(preferences: preferences,
                                                         onCreated: onCustomPreferenceCreated)
    }

    private func saveAndAnalyze(name: String) {
        onCreatePreference(selection.photos, name) { result in
            switch result {
            case .success(let id):
                selection.markPreferenceCreated(id: id, photos: selection.photos)
                onStartAnalyzing(id)
            case .failure(let error):
                updateError = error.message
            }
        }
    }

    private func openPicker() {
        guard !selection.isSavingPhotos, !selection.isStartingAnalysis else { return }
        isPresentingPicker = true
    }

    private var isAddingDisabled: Bool {
        selection.isSavingPhotos || selection.isStartingAnalysis || (selection.hasSavedPreference && !selection.isPersistedPreferenceLoaded)
    }

    private var hasUnsavedPhotos: Bool {
        !selection.photos.isEmpty && !selection.hasSavedPreference
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

    func removePhotos(withIDs ids: Set<UUID>) {
        guard !hasSavedPreference else { return }
        photos.removeAll { ids.contains($0.id) }
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
