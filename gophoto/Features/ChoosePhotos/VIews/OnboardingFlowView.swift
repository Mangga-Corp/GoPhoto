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
    /// The style card's primary action. Returns an error message if the destination cannot be opened.
    var onFinish: () -> String?
    let preferenceID: UUID
    let onAnalysisCompleted: () -> Void
    let styleButtonTitle: String
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
        styleButtonTitle: String = "Open Camera",
        onAnalysisCompleted: @escaping () -> Void,
        onChooseOtherPhotos: (() -> Void)? = nil,
        onFinish: @escaping () -> String?
    ) {
        self.preferenceID = preferenceID
        self.onAnalysisCompleted = onAnalysisCompleted
        self.styleButtonTitle = styleButtonTitle
        self.onChooseOtherPhotos = onChooseOtherPhotos
        self.onFinish = onFinish
        let preference = PreferencesViewModel.shared.preference(id: preferenceID)
        let usable = preference?.analysis.map { $0.isCurrent && $0.usability == .usable } ?? false
        let summary = usable ? StyleSummary(analysis: preference?.analysis, photos: preference?.photos ?? []) : nil
        _style = State(initialValue: (startsAtStyleCard || usable) ? summary : nil)
        let currentAnalysis = preference?.analysis.flatMap { $0.isCurrent ? $0 : nil }
        let recoveredFailure: AnalysisFailure?
        if !startsAtStyleCard, let analysis = currentAnalysis, !usable {
            switch analysis.usability {
            case .usable: recoveredFailure = nil
            case .requiredAnalysisFailed: recoveredFailure = .analysisFailed
            case .noUsableFraming: recoveredFailure = .noUsableFraming
            }
        } else {
            recoveredFailure = nil
        }
        _failure = State(initialValue: recoveredFailure)
    }

    var body: some View {
        ZStack {
            if let style {
                StyleScreen(summary: style, buttonTitle: styleButtonTitle, onDone: finish)
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
        .onAppear {
            if style != nil { onAnalysisCompleted() }
        }
        .alert("Couldn't open the camera", isPresented: Binding(get: { finishError != nil },
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
                .font(AppFont.system(size: 36))
                .foregroundStyle(failure == .noUsableFraming ? GoPhotoDesign.secondaryText : GoPhotoDesign.warning)
            Text(failure == .noUsableFraming ? "We couldn't find a person in these photos."
                                             : "We couldn't read your photos.")
                .font(GoPhotoDesign.sectionTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)
            Text(failure == .noUsableFraming ? "Choose photos that clearly show one person."
                                             : "Your photos are safe. Please try again.")
                .font(GoPhotoDesign.secondaryBody)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.goPhotoPrimary)
                .accessibilityIdentifier("analysis.retry")
            if let onChooseOtherPhotos {
                Button("Choose Other Photos", action: onChooseOtherPhotos)
                    .buttonStyle(.goPhotoSecondary)
                    .accessibilityIdentifier("analysis.chooseOtherPhotos")
            }
            #if DEBUG
            if DebugFixtures.storeName != nil {
                Text("analysisRuns=\(PreferencesViewModel.shared.analysisRunCount)")
                    .font(AppFont.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("debug.analysisRuns")
            }
            #endif
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoPhotoDesign.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis.failure")
    }
}

private struct StyleScreen: UIViewControllerRepresentable {
    let summary: StyleSummary
    let buttonTitle: String
    var onDone: () -> Void

    func makeUIViewController(context: Context) -> StyleCardViewController {
        let vc = StyleCardViewController(summary: summary, buttonTitle: buttonTitle)
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
