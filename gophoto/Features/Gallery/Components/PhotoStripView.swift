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
    /// Shared with PhotoPagerView: swipe the pager → strip follows, tap the strip → pager follows
    @Binding var currentID: String
    let loadThumbnail: (String, CGSize) async -> UIImage?

    private let itemSize: CGFloat = 40

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(photos) { photo in
                        let isCurrent = photo.assetID == currentID

                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                currentID = photo.assetID
                            }
                        } label: {
                            VStack(spacing: 4) {
                                // Indikator titik ungu di atas thumbnail yang aktif
                                Circle()
                                    .fill(isCurrent ? Color(hex: 0x9A69C9) : Color.clear)
                                    .frame(width: 5, height: 5)

                                GalleryThumbnailView(assetID: photo.assetID,
                                                     createdAt: photo.createdAt,
                                                     loadThumbnail: loadThumbnail)
                                    .frame(width: itemSize, height: itemSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay {
                                        if isCurrent {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color(hex: 0x9A69C9), lineWidth: 2)
                                        }
                                    }
                                    .opacity(isCurrent ? 1 : 0.6)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(photo.assetID)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            // Centre the current photo when the strip appears…
            .onAppear { proxy.scrollTo(currentID, anchor: .center) }
            // …and whenever the photo changes (swipe or tap)
            .onChange(of: currentID) { _, newID in
                withAnimation { proxy.scrollTo(newID, anchor: .center) }
            }
        }
        .padding(.vertical, 4)
    }
}
