//
//  PhotoStripView.swift
//  gophoto
//
//  Created by Reynard Setiawan on 14/10/26.
//
//  DBM-77: thumbnail strip under the full-screen viewer, like the Photos app.
//  Scrolls sideways; the current photo is highlighted and kept centred;
//  tapping a thumbnail shows that photo. Plain values in, no ViewModel.
//

import SwiftUI

struct PhotoStripView: View {
    let photos: [GalleryPhoto]
    @Binding var currentID: String
    let loadThumbnail: (String, CGSize) async -> UIImage?

    private let itemSize: CGFloat = 34

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(photos, id: \.assetID) { photo in
                        thumbnail(for: photo)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, max(0, (proxy.size.width - itemSize) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: centredID, anchor: .center)
        }
        .frame(height: itemSize + 12)
    }

    private var centredID: Binding<String?> {
        Binding(get: { currentID },
                set: { if let id = $0, id != currentID { currentID = id } })
    }

    private func thumbnail(for photo: GalleryPhoto) -> some View {
        let isCurrent = photo.assetID == currentID
        return Button {
            withAnimation(.snappy) { currentID = photo.assetID }
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(isCurrent ? Color(hex: 0x9A69C9) : Color.clear)
                    .frame(width: 5, height: 5)
                GalleryThumbnailView(assetID: photo.assetID,
                                     createdAt: photo.createdAt,
                                     loadThumbnail: loadThumbnail)
                    .frame(width: itemSize, height: itemSize)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color(hex: 0x9A69C9), lineWidth: 2)
                        }
                    }
                    .opacity(isCurrent ? 1 : 0.6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
