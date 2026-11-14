import SwiftUI

struct PhotoReviewView: View {
    @State private var viewModel: PhotoReviewViewModel
    private let leftOut: [PersonPhoto]
    private let onContinue: ([PhotoItem]) -> Void

    init(candidates: [PersonPhoto], leftOut: [PersonPhoto] = [], onContinue: @escaping ([PhotoItem]) -> Void) {
        _viewModel = State(initialValue: PhotoReviewViewModel(candidates: candidates))
        self.leftOut = leftOut
        self.onContinue = onContinue
    }

    var body: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - GoPhotoDesign.sessionMargin * 2 - 20) / 3
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your photos")
                        .font(GoPhotoDesign.largeTitle)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                    Text("We picked the best ones. Tap a photo to change the selection.")
                        .font(GoPhotoDesign.body)
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    switch viewModel.state {
                    case .grading:
                        ProgressView("Checking photo quality…")
                    case .ready, .loading:
                        grid(width: width)
                        footer
                    case .failed(let text):
                        Text(text)
                            .font(GoPhotoDesign.body)
                            .foregroundStyle(GoPhotoDesign.error)
                    }
                }
                .padding(GoPhotoDesign.sessionMargin)
                .padding(.bottom, 80)
            }
        }
        .background(GoPhotoDesign.background)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.grade() }
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue with \(viewModel.selectedCount) photos",
                                 isEnabled: viewModel.canContinue,
                                 isLoading: viewModel.state == .loading) {
                Task {
                    if let items = await viewModel.loadSelection() { onContinue(items) }
                }
            }
        }
    }

    private func grid(width: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 10), count: 3), spacing: 10) {
            ForEach(viewModel.photos) { photo in
                let isSelected = viewModel.isSelected(photo.id)
                Button { viewModel.toggle(photo.id) } label: {
                    PhotoThumbnail(url: photo.thumbnailURL, width: width)
                        .overlay(alignment: .topTrailing) {
                            SelectionMark(isSelected: isSelected).padding(6)
                        }
                        .opacity(isSelected || !viewModel.isFull ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(viewModel.selectedCount) of \(PhotoReviewViewModel.maxPhotos) selected · at least \(PhotoReviewViewModel.minPhotos) needed")
            if viewModel.droppedCount > 0 {
                Text("\(viewModel.droppedCount) photos were left out for blur or lighting.")
            }
        }
        .font(GoPhotoDesign.caption)
        .foregroundStyle(GoPhotoDesign.secondaryText)

        #if DEBUG
        if !leftOut.isEmpty {
            Text("Debug · left out as group photos: \(leftOut.count)")
                .font(GoPhotoDesign.cardTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .padding(.top, 12)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                ForEach(leftOut) { photo in
                    PhotoThumbnail(url: photo.thumbnailURL, width: 72)
                }
            }
        }
        #endif
    }
}

private struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? GoPhotoDesign.primary : Color.black.opacity(0.3))
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .strokeBorder(.white, lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }
        }
    }
}
