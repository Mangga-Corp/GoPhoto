import Observation
import SwiftUI

struct PhotoSessionSetupView: View {
    @State private var selection = PhotoSessionSetupSelection()
    @State private var isPresentingPicker = false
    @State private var isPresentingNamePrompt = false
    @State private var isShowingCustomPreference = false

    let onCreatePreference: ([PhotoItem], String, @escaping (String?) -> Void) -> Void

    init(
        savedPreference: Preference? = nil,
        onCreatePreference: @escaping ([PhotoItem], String, @escaping (String?) -> Void) -> Void
    ) {
        _selection = State(initialValue: PhotoSessionSetupSelection(
            photos: savedPreference?.photos ?? [],
            hasCreatedPreference: savedPreference != nil
        ))
        self.onCreatePreference = onCreatePreference
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
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(GoPhotoDesign.sessionBackground)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actions
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $isShowingCustomPreference) {
                CustomPreferenceBuilderPlaceholderView()
            }
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.sessionAccent)
        .fullScreenCover(isPresented: $isPresentingPicker) {
            PhotoSessionPhotoPicker(
                initialPhotos: selection.photos,
                onSelection: selection.replace(with:),
                onFinish: { isPresentingPicker = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isPresentingNamePrompt) {
            PhotoSessionPhotoPicker(
                photosToName: selection.photos,
                onCreatePreference: { photos, name, completion in
                    onCreatePreference(photos, name) { error in
                        if error == nil { selection.markPreferenceCreated() }
                        completion(error)
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
                if !selection.hasCreatedPreference {
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
            if selection.hasCreatedPreference {
                Text("Preference saved")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GoPhotoDesign.sessionAccent)
                    .frame(maxWidth: .infinity, minHeight: 58)
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
    }

    private func openPicker() {
        isPresentingPicker = true
    }
}

@Observable
final class PhotoSessionSetupSelection {
    private(set) var photos: [PhotoItem]
    private(set) var hasCreatedPreference: Bool

    var canContinue: Bool {
        !hasCreatedPreference && photos.count >= ChoosePhotosViewModel.minPhotos
    }

    init(photos: [PhotoItem] = [], hasCreatedPreference: Bool = false) {
        self.photos = photos
        self.hasCreatedPreference = hasCreatedPreference
    }

    func replace(with newPhotos: [PhotoItem]) {
        guard !hasCreatedPreference else { return }
        photos = []
        append(newPhotos)
    }

    func remove(photoID: UUID) {
        guard !hasCreatedPreference else { return }
        photos.removeAll { $0.id == photoID }
    }

    func markPreferenceCreated() {
        hasCreatedPreference = true
    }

    private func append(_ newPhotos: [PhotoItem]) {
        var assetIdentifiers = Set<String>()
        var itemIdentifiers = Set<UUID>()
        for photo in newPhotos {
            guard photos.count < ChoosePhotosViewModel.maxPhotos else { return }
            if let sourceAssetIdentifier = photo.sourceAssetIdentifier {
                guard assetIdentifiers.insert(sourceAssetIdentifier).inserted else { continue }
            } else {
                guard itemIdentifiers.insert(photo.id).inserted else { continue }
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
