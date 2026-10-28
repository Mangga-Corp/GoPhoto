//
//  OnboardingFlowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI

/// First-launch flow: Photos permission -> Preferences (pick photos) -> analysis -> "Your style"
/// card -> onFinish.
struct OnboardingFlowView: View {
    var onFinish: () -> Void
    @State private var pickedPhotos: [PhotoItem]?
    @State private var style: StyleSummary?

    var body: some View {
        ZStack {
            if let style {
                StyleScreen(summary: style,
                            presetName: PreferencesViewModel.shared.selectedPreference?.name ?? "",
                            onDone: onFinish)
                    .transition(.opacity)
            } else if let pickedPhotos {
                AnalyzingScreen(photos: pickedPhotos) {
                    let preference = PreferencesViewModel.shared.selectedPreference
                    guard let summary = StyleSummary(analysis: preference?.analysis,
                                                     photos: preference?.photos ?? []) else {
                        onFinish()
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.4)) { style = summary }
                }
                .transition(.opacity)
            } else {
                PreferencesScreen { photos, name in
                    PreferencesViewModel.shared.addFirstPreference(name: name, photos: photos)
                    withAnimation(.easeInOut(duration: 0.4)) { pickedPhotos = photos }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }
}

private struct PreferencesScreen: UIViewControllerRepresentable {
    var onPhotosPicked: ([PhotoItem], String) -> Void

    func makeUIViewController(context: Context) -> AIPreferencesViewController {
        let viewModel = ChoosePhotosViewModel(service: ChoosePhotosService(),
                                              preferenceName: "Preferences", items: [], mode: .onboarding)
        let vc = AIPreferencesViewController(viewModel: viewModel)
        vc.onPhotosAdded = onPhotosPicked
        return vc
    }
    func updateUIViewController(_ vc: AIPreferencesViewController, context: Context) {}
}

private struct StyleScreen: UIViewControllerRepresentable {
    let summary: StyleSummary
    let presetName: String
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> StyleCardViewController {
        let vc = StyleCardViewController(summary: summary, presetName: presetName)
        vc.onDone = onDone
        return vc
    }
    func updateUIViewController(_ vc: StyleCardViewController, context: Context) {}
}

private struct AnalyzingScreen: UIViewControllerRepresentable {
    let photos: [PhotoItem]
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> AnalyzingViewController {
        let vc = AnalyzingViewController(viewModel: AnalyzingViewModel(preferenceID: PreferencesViewModel.shared.selectedID),
                                         photos: photos)
        vc.onFinish = onFinish
        return vc
    }
    func updateUIViewController(_ vc: AnalyzingViewController, context: Context) {}
}
