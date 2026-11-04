//
//  PreferencePhotoPager.swift
//  gophoto
//
//  Full-screen viewer for a preference's photos, like the app's gallery: swipe between photos,
//  pinch / double-tap to zoom (same ZoomableImageView), swipe down or ✕ to close.
//  Plain values in, no ViewModel.
//

import SwiftUI

/// A photo's posture as shown: what it counts as, and whether the user set it.
struct PhotoPostureInfo: Equatable {
    var posture: Posture?
    var isManual: Bool
}

struct PreferencePhotoPager: View {
    let images: [UIImage]
    /// Per photo, e.g. "Full body"; nil when not analysed.
    let labels: [String?]
    let onPageChange: (Int) -> Void
    let onClose: () -> Void
    /// Sets a photo's posture (nil = automatic) and returns what it shows afterwards. Nil = no menu.
    let onSetPosture: ((Int, Posture?) -> PhotoPostureInfo)?

    @State private var current: Int
    @State private var postures: [PhotoPostureInfo]

    init(images: [UIImage], labels: [String?], postures: [PhotoPostureInfo]? = nil, startIndex: Int,
         onSetPosture: ((Int, Posture?) -> PhotoPostureInfo)? = nil,
         onPageChange: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.images = images
        self.labels = labels
        self.onPageChange = onPageChange
        self.onClose = onClose
        self.onSetPosture = onSetPosture
        _current = State(initialValue: startIndex)
        _postures = State(initialValue: postures ?? images.map { _ in PhotoPostureInfo(posture: nil, isManual: false) })
    }

    var body: some View {
        ZStack(alignment: .top) {
            GoPhotoDesign.background.ignoresSafeArea()

            TabView(selection: $current) {
                ForEach(images.indices, id: \.self) { index in
                    ZoomableImageView(image: images[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))   // swipe pages, like Photos
            .ignoresSafeArea()

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .frame(width: 44, height: 44)
                        .background(GoPhotoDesign.subtleSurface, in: Circle())
                }
                .accessibilityLabel("Close")
                Spacer()
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GoPhotoDesign.primaryText)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(GoPhotoDesign.subtleSurface, in: Capsule())
                Spacer()
                if onSetPosture != nil {
                    postureMenu
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 12)
        }
        .statusBarHidden(true)
        .onChange(of: current) { _, page in onPageChange(page) }
    }

    private var info: PhotoPostureInfo {
        postures.indices.contains(current) ? postures[current] : PhotoPostureInfo(posture: nil, isManual: false)
    }

    /// Standing / Sitting / Automatic for the photo on screen.
    private var postureMenu: some View {
        Menu {
            Button { set(.standing) } label: {
                Label("Standing", systemImage: info.isManual && info.posture == .standing ? "checkmark" : "figure.stand")
            }
            Button { set(.sitting) } label: {
                Label("Sitting", systemImage: info.isManual && info.posture == .sitting ? "checkmark" : "figure.seated.side")
            }
            Button { set(nil) } label: {
                Label("Automatic", systemImage: info.isManual ? "wand.and.stars" : "checkmark")
            }
        } label: {
            Image(systemName: info.posture == .sitting ? "figure.seated.side" : "figure.stand")
                .font(.body.weight(.semibold))
                .foregroundStyle(GoPhotoDesign.primaryText)
                .frame(width: 44, height: 44)
                .background(GoPhotoDesign.subtleSurface, in: Circle())
        }
        .accessibilityLabel("Posture of this photo")
    }

    private func set(_ posture: Posture?) {
        guard let onSetPosture, postures.indices.contains(current) else { return }
        postures[current] = onSetPosture(current, posture)
    }

    private var title: String {
        var parts = ["\(current + 1) of \(images.count)"]
        if labels.indices.contains(current), let label = labels[current] { parts.append(label) }
        if let posture = info.posture {
            parts.append((posture == .sitting ? "Sitting" : "Standing") + (info.isManual ? "" : " (auto)"))
        }
        return parts.joined(separator: " · ")
    }
}
