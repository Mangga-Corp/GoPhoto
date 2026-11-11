//
//  GalleryScreen.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  The gallery as presented from the camera.
//  A separate view with no inputs, so SwiftUI never rebuilds it (or its view model) when the
//  camera screen underneath updates.
//

import SwiftUI

struct GalleryScreen: View {
    /// Created once for the life of the screen
    @State private var viewModel = GalleryViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GalleryView(viewModel: viewModel, onDismiss: { dismiss() })
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.primary)
    }
}
