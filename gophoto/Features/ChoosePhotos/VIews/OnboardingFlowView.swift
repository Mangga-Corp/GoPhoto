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
    @State private var analysisFailed = false
    @State private var analysisRetry = 0

    init(onFinish: @escaping () -> Void, resumeExistingPreference: Bool = false) {
        self.onFinish = onFinish
        let photos = resumeExistingPreference
            ? PreferencesViewModel.shared.selectedPreference?.photos
            : nil
        _pickedPhotos = State(initialValue: photos?.isEmpty == false ? photos : nil)
    }

    var body: some View {
        ZStack {
            if let style {
                StyleScreen(summary: style,
                            presetName: PreferencesViewModel.shared.selectedPreference?.name ?? "",
                            onDone: onFinish)
                    .transition(.opacity)
            } else if analysisFailed {
                AnalysisRetryScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        analysisFailed = false
                        analysisRetry += 1
                    }
                }
                .transition(.opacity)
            } else if let pickedPhotos {
                AnalyzingScreen(photos: pickedPhotos) {
                    let preference = PreferencesViewModel.shared.selectedPreference
                    guard let summary = StyleSummary(analysis: preference?.analysis,
                                                     photos: preference?.photos ?? []) else {
                        withAnimation(.easeInOut(duration: 0.4)) { analysisFailed = true }
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.4)) { style = summary }
                }
                .transition(.opacity)
                .id(analysisRetry)
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

private struct AnalysisRetryScreen: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("We couldn't finish your photo analysis.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: Theme.background))
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
