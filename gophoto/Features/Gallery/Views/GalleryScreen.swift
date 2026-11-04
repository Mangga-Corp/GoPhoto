//
//  GalleryScreen.swift
//  gophoto
//
//  The gallery as presented from the camera: navigation + back button.
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
            GalleryView(viewModel: viewModel)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back")
                    }
                }
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.purple)
    }
}
