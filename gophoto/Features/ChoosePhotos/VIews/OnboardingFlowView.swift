//
//  OnboardingFlowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI
import os

/// Runs the analysis of a newly created preference and shows its "Your style" card (first launch,
/// and Add New Preference). The card appears only when the analysis is usable: a run whose
/// required Vision requests failed, or that found no readable framing, shows the retry screen.
struct OnboardingFlowView: View {
    /// The style card's button. Returns an error message when the camera session could not be
    /// started (the card stays, with the message), or nil when it started.
    var onFinish: () -> String?
    let preferenceID: UUID
    let onAnalysisCompleted: () -> Void
    /// "Choose Other Photos" on the no-person screen; nil hides the button.
    let onChooseOtherPhotos: (() -> Void)?
    @State private var style: StyleSummary?
    @State private var failure: AnalysisFailure?
    @State private var analysisRetry = 0
    @State private var finishError: String?

    private static let log = Logger(subsystem: "co.mango.gophoto", category: "analysis")

    enum AnalysisFailure: Equatable {
        /// Cancelled, or a required request failed: running it again can help.
        case analysisFailed
        /// It ran, but no photo showed a readable person: other photos are needed.
        case noUsableFraming
    }

    init(
        preferenceID: UUID,
        startsAtStyleCard: Bool,
        onAnalysisCompleted: @escaping () -> Void,
        onChooseOtherPhotos: (() -> Void)? = nil,
        onFinish: @escaping () -> String?
    ) {
        self.preferenceID = preferenceID
        self.onAnalysisCompleted = onAnalysisCompleted
        self.onChooseOtherPhotos = onChooseOtherPhotos
        self.onFinish = onFinish
        let preference = PreferencesViewModel.shared.preference(id: preferenceID)
        let usable = preference?.analysis.map { $0.isCurrent && $0.usability == .usable } ?? false
        let summary = usable ? StyleSummary(analysis: preference?.analysis, photos: preference?.photos ?? []) : nil
        _style = State(initialValue: startsAtStyleCard ? summary : nil)
    }

    var body: some View {
        ZStack {
            if let style {
                StyleScreen(summary: style, onDone: finish)
                    .transition(.opacity)
            } else if let failure {
                AnalysisRetryScreen(failure: failure,
                                    onChooseOtherPhotos: failure == .noUsableFraming ? onChooseOtherPhotos : nil) {
                    // Same photos, analysed again (a new run; the photos stay saved).
                    withAnimation(.easeInOut(duration: 0.4)) {
                        self.failure = nil
                        analysisRetry += 1
                    }
                }
                .transition(.opacity)
            } else if let preference = PreferencesViewModel.shared.preference(id: preferenceID) {
                AnalyzingScreen(preferenceID: preferenceID, photos: preference.photos) {
                    analysisFinished()
                }
                .transition(.opacity)
                .id(analysisRetry)
            } else {
                AnalysisRetryScreen(failure: .analysisFailed, onChooseOtherPhotos: onChooseOtherPhotos) {
                    withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .alert("Couldn't start shooting", isPresented: Binding(get: { finishError != nil },
                                                              set: { if !$0 { finishError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(finishError ?? "")
        }
    }

    private func analysisFinished() {
        let preference = PreferencesViewModel.shared.preference(id: preferenceID)
        guard let analysis = preference?.analysis, analysis.isCurrent else {
            Self.log.error("Analysis of \(preferenceID) produced no current result")
            withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
            return
        }
        switch analysis.usability {
        case .usable:
            guard let preference, let summary = StyleSummary(analysis: analysis, photos: preference.photos) else {
                withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
                return
            }
            onAnalysisCompleted()
            withAnimation(.easeInOut(duration: 0.4)) { style = summary }
        case .requiredAnalysisFailed:
            Self.log.error("Required analysis failed for \(preferenceID): \(analysis.evidence?.diagnosticDescription ?? "")")
            withAnimation(.easeInOut(duration: 0.4)) { failure = .analysisFailed }
        case .noUsableFraming:
            Self.log.notice("Analysis of \(preferenceID) found no readable framing")
            withAnimation(.easeInOut(duration: 0.4)) { failure = .noUsableFraming }
        }
    }

    private func finish() {
        finishError = onFinish()
    }
}

private struct AnalysisRetryScreen: View {
    let failure: OnboardingFlowView.AnalysisFailure
    let onChooseOtherPhotos: (() -> Void)?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: failure == .noUsableFraming ? "person.fill.questionmark"
                                                          : "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(failure == .noUsableFraming ? "We couldn't find a person in these photos."
                                             : "We couldn't finish your photo analysis.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(failure == .noUsableFraming ? "Choose photos that clearly show one person."
                                             : "Your photos are saved. Try the analysis again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("analysis.retry")
            if let onChooseOtherPhotos {
                Button("Choose Other Photos", action: onChooseOtherPhotos)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("analysis.chooseOtherPhotos")
            }
            #if DEBUG
            if DebugFixtures.storeName != nil {
                Text("analysisRuns=\(PreferencesViewModel.shared.analysisRunCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("debug.analysisRuns")
            }
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: Theme.background))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis.failure")
    }
}

private struct StyleScreen: UIViewControllerRepresentable {
    let summary: StyleSummary
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> StyleCardViewController {
        let vc = StyleCardViewController(summary: summary)
        vc.onDone = onDone
        return vc
    }
    func updateUIViewController(_ vc: StyleCardViewController, context: Context) {
        vc.onDone = onDone
    }
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
