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

    private let itemSize: CGFloat = 44   // HIG minimum tap target

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(photos) { photo in
                        let isCurrent = photo.assetID == currentID

                        Button {
                            withAnimation { currentID = photo.assetID }
                        } label: {
                            GalleryThumbnailView(assetID: photo.assetID,
                                                 createdAt: photo.createdAt,
                                                 loadThumbnail: loadThumbnail)
                                .frame(width: itemSize, height: itemSize)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay {
                                    if isCurrent {
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(.primary, lineWidth: 2)
                                    }
                                }
                                .opacity(isCurrent ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                        .id(photo.assetID)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: itemSize)
            }
            .scrollIndicators(.hidden)
            // Centre the current photo when the strip appears…
            .onAppear { proxy.scrollTo(currentID, anchor: .center) }
            // …and whenever the photo changes (swipe or tap)
            .onChange(of: currentID) { _, newID in
                withAnimation { proxy.scrollTo(newID, anchor: .center) }
            }
        }
        .padding(.vertical, 8)
    }
}
