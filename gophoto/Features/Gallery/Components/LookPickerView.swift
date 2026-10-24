//
//  LookPickerView.swift
//  gophoto
//
//  Row under the full-screen viewer: the photo as it is, plus the five AI Enhanced looks, each
//  previewed on a small copy of the current photo. Tap a look to preview it, tap it again (or
//  "Original") to go back. Nothing is saved here: saving goes through the share sheet.
//

import SwiftUI

struct LookPickerView: View {
    let assetID: String
    @Binding var selection: EnhancedLook?
    let loadThumbnail: (String, CGSize) async -> UIImage?

    @Environment(\.displayScale) private var displayScale
    @State private var previews: [EnhancedLook: UIImage] = [:]
    @State private var original: UIImage?

    private let itemSize: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                chip(title: "Original", image: original, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(EnhancedLook.allCases) { look in
                    chip(title: look.title, image: previews[look], isSelected: selection == look) {
                        selection = (selection == look) ? nil : look
                    }
                    .accessibilityHint(look.summary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        // Rebuilt for every photo; cancelled if the user swipes on before it finishes
        .task(id: assetID) { await loadPreviews() }
    }

    private func chip(title: String, image: UIImage?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: itemSize, height: itemSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func loadPreviews() async {
        previews = [:]
        original = nil
        let side = itemSize * 2 * displayScale   // sharp enough, still cheap to filter five times
        guard let thumb = await loadThumbnail(assetID, CGSize(width: side, height: side)) else { return }
        original = thumb
        for look in EnhancedLook.allCases {
            let image = await Task.detached(priority: .userInitiated) {
                PhotoEnhancer().enhance(thumb, look: look)
            }.value
            guard !Task.isCancelled else { return }
            previews[look] = image
        }
    }
}
