import SwiftUI

struct FacePickerView: View {
    @State private var viewModel = FacePickerViewModel()
    @State private var isShowingLimitedAccessAlert = false
    @State private var isShowingReview = false
    @Environment(\.openURL) private var openURL

    let onPhotosChosen: ([PhotoItem]) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Which one is you?")
                    .font(GoPhotoDesign.largeTitle)
                    .foregroundStyle(GoPhotoDesign.primaryText)
                content
            }
            .padding(GoPhotoDesign.sessionMargin)
        }
        .background(GoPhotoDesign.background)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.start() }
        .onDisappear { if !isShowingReview { viewModel.clear() } }
        .onChange(of: viewModel.state) { _, state in
            isShowingLimitedAccessAlert = state == .limitedAccess
        }
        .alert("Works best with full access", isPresented: $isShowingLimitedAccessAlert) {
            Button("Open Settings") {
                viewModel.dismissLimitedAccess()
                openSettings()
            }
            Button("Continue anyway") { viewModel.continueWithLimitedAccess() }
            Button("Cancel", role: .cancel) { viewModel.dismissLimitedAccess() }
        } message: {
            Text("Poto can only look through the photos you've shared with it. Allow access to all photos in Settings to find more photos of you.")
        }
        .navigationDestination(isPresented: $isShowingReview) {
            PhotoReviewView(candidates: viewModel.includedPhotos, leftOut: viewModel.groupPhotos) { items in
                viewModel.clear()
                onPhotosChosen(items)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .limitedAccess:
            SessionPrimaryButton(title: "Scan my photos") { viewModel.start() }
        case .unsupported:
            message("Finding your photos automatically needs iOS 27. Choose photos yourself instead.")
        case .needsAccess:
            message("Allow Poto to access your photos in Settings to scan them.")
            Button("Open Settings", action: openSettings)
                .buttonStyle(.goPhotoText)
        case .scanning(let progress):
            ProgressView("Looking for faces… \(progress.photosChecked) photos, \(progress.facesFound) faces")
            Button("Cancel") { viewModel.cancelScan() }
                .buttonStyle(.goPhotoText)
        case .done:
            if viewModel.groups.isEmpty {
                message("No faces found in your recent photos.")
            } else {
                people
            }
        case .failed(let text):
            message(text)
            Button("Try again") { viewModel.start() }
                .buttonStyle(.goPhotoText)
        }
    }

    private var people: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                ForEach(viewModel.shownGroups) { group in
                    Button {
                        viewModel.pick(group)
                        isShowingReview = true
                    } label: {
                        VStack(spacing: 6) {
                            PersonCover(image: viewModel.covers[group.id])
                            Text("\(group.assetIDs.count) photos")
                                .font(GoPhotoDesign.caption)
                                .foregroundStyle(GoPhotoDesign.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if viewModel.hasMoreGroups {
                Button("Not here? Show more people") { viewModel.showAllGroups() }
                    .buttonStyle(.goPhotoText)
            }
            Text("\(viewModel.groups.count) people from \(viewModel.faceCount) faces in \(viewModel.photosChecked) photos")
                .font(GoPhotoDesign.caption)
                .foregroundStyle(GoPhotoDesign.secondaryText)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(GoPhotoDesign.body)
            .foregroundStyle(GoPhotoDesign.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

private struct PersonCover: View {
    let image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Circle().fill(GoPhotoDesign.primarySubtle)
                    .overlay { Image(systemName: "person.fill").foregroundStyle(GoPhotoDesign.primary) }
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
    }
}
