//
//  OnboardingFlowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI

/// First-launch flow: Photos permission -> Preferences (pick photos) -> analysis -> onFinish.
struct OnboardingFlowView: View {
    var onFinish: () -> Void
    @State private var pickedPhotos: [PhotoItem]?

    var body: some View {
        ZStack {
            if let pickedPhotos {
                AnalyzingScreen(photos: pickedPhotos, onFinish: onFinish)
                    .transition(.opacity)
            } else {
                PreferencesScreen { photos in
                    PreferencesViewModel.shared.addFirstPreference(name: "My Preference", photos: photos)
                    withAnimation(.easeInOut(duration: 0.4)) { pickedPhotos = photos }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
}

private struct PreferencesScreen: UIViewControllerRepresentable {
    var onPhotosPicked: ([PhotoItem]) -> Void

    func makeUIViewController(context: Context) -> AIPreferencesViewController {
        let viewModel = ChoosePhotosViewModel(service: ChoosePhotosService(),
                                              preferenceName: "Preferences", items: [], mode: .onboarding)
        let vc = AIPreferencesViewController(viewModel: viewModel)
        vc.onPhotosAdded = onPhotosPicked
        return vc
    }
    func updateUIViewController(_ vc: AIPreferencesViewController, context: Context) {}
}

private struct AnalyzingScreen: UIViewControllerRepresentable {
    let photos: [PhotoItem]
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> AnalyzingViewController {
        let vc = AnalyzingViewController(viewModel: AnalyzingViewModel(), photos: photos)
        vc.onFinish = onFinish
        return vc
    }
    func updateUIViewController(_ vc: AnalyzingViewController, context: Context) {}
}
