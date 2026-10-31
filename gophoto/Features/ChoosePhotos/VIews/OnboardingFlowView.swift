//
//  OnboardingFlowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI

/// Resumes analysis and the "Your style" card for the preference created during first launch.
struct OnboardingFlowView: View {
    var onFinish: () -> Void
    let preferenceID: UUID
    let onAnalysisCompleted: () -> Void
    @State private var style: StyleSummary?
    @State private var analysisFailed = false
    @State private var analysisRetry = 0

    init(
        preferenceID: UUID,
        startsAtStyleCard: Bool,
        onAnalysisCompleted: @escaping () -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.preferenceID = preferenceID
        self.onAnalysisCompleted = onAnalysisCompleted
        self.onFinish = onFinish
        let preference = PreferencesViewModel.shared.preference(id: preferenceID)
        let summary = StyleSummary(analysis: preference?.analysis, photos: preference?.photos ?? [])
        _style = State(initialValue: startsAtStyleCard ? summary : nil)
    }

    var body: some View {
        ZStack {
            if let style {
                StyleScreen(summary: style,
                            presetName: PreferencesViewModel.shared.preference(id: preferenceID)?.name ?? "",
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
            } else if let preference = PreferencesViewModel.shared.preference(id: preferenceID) {
                AnalyzingScreen(preferenceID: preferenceID, photos: preference.photos) {
                    guard let preference = PreferencesViewModel.shared.preference(id: preferenceID),
                          preference.analysis?.isCurrent == true,
                          let summary = StyleSummary(analysis: preference.analysis, photos: preference.photos) else {
                        withAnimation(.easeInOut(duration: 0.4)) { analysisFailed = true }
                        return
                    }
                    onAnalysisCompleted()
                    withAnimation(.easeInOut(duration: 0.4)) {
                        style = summary
                    }
                }
                .transition(.opacity)
                .id(analysisRetry)
            } else {
                AnalysisRetryScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        analysisFailed = true
                    }
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
    let preferenceID: UUID
    let photos: [PhotoItem]
    var onFinish: () -> Void

    func makeUIViewController(context: Context) -> AnalyzingViewController {
        let vc = AnalyzingViewController(viewModel: AnalyzingViewModel(preferenceID: preferenceID),
                                         photos: photos)
        vc.onFinish = onFinish
        return vc
    }
    func updateUIViewController(_ vc: AnalyzingViewController, context: Context) {}
}
