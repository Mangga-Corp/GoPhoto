//
//  ShotSizeSelectionView.swift
//  gophoto
//
//  "Choose Your Shot Size": the requested framing for the session being configured. Starts at
//  3/4 Body every time. Start Shooting hands a validated `PhotoSessionConfiguration` on; it does
//  not start the session (Phase 4) and nothing here is saved.
//

import SwiftUI

struct ShotSizeSelectionView: View {
    let model: ShotSizeSelectionViewModel
    /// Start Shooting, with a configuration resolved at the tap. The flow starts the session
    /// (resolving it again) and returns the error when it could not; nil = started.
    let onStartShooting: (PhotoSessionConfiguration) -> PhotoSessionError?

    @Environment(\.dismiss) private var dismiss
    /// Set by the first tap: a second tap can't start a second session.
    @State private var isStarting = false
    @State private var startError: PhotoSessionError?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                eyebrow
                    .padding(.top, 8)

                Text("Choose Your Shot Size")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(GoPhotoDesign.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 12)
                Text("How would you like your subject framed?")
                    .font(.system(size: 17))
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                VStack(spacing: 14) {
                    ForEach(SessionShotSize.allCases, id: \.self) { shot in
                        ShotSizeCard(shot: shot, isSelected: model.selectedShotSize == shot)
                            .onTapGesture { model.select(shot) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(model.selectedShotSize == shot ? [.isButton, .isSelected] : .isButton)
                            .accessibilityIdentifier("shotSizeCard.\(shot.rawValue)")
                    }
                }
                .padding(.top, 26)

                if let notice = model.notice {
                    ShotSizeNoticeView(notice: notice)
                        .padding(.top, 16)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, GoPhotoDesign.sessionMargin)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.2), value: model.notice)
        }
        .scrollIndicators(.hidden)
        .background(GoPhotoDesign.sessionBackground.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sessionBottomBar {
            SessionPrimaryButton(title: "START SHOOTING", systemImage: "arrow.right",
                                 isEnabled: model.canStartShooting && !isStarting) {
                startShooting()
            }
            .accessibilityIdentifier("shotSize.startShooting")
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("Couldn't start shooting", isPresented: Binding(get: { startError != nil },
                                                              set: { if !$0 { startError = nil } }),
               presenting: startError) { error in
            Button("OK", role: .cancel) {
                // The preference is gone: back to Preference Selection, which has a valid state.
                if error == .preferenceNotFound { dismiss() }
            }
        } message: { error in
            Text(error.message)
        }
    }

    private func startShooting() {
        guard !isStarting else { return }
        // Resolved again at the tap: never a deleted preference or a stale analysis.
        guard let configuration = model.makeConfiguration() else { return }
        isStarting = true
        if let error = onStartShooting(configuration) {
            startError = error
            isStarting = false
        }
        // Started: the app shows the camera; this screen goes away.
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(GoPhotoDesign.primaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            .accessibilityIdentifier("shotSize.back")
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background(GoPhotoDesign.sessionBarBackground.ignoresSafeArea(edges: .top))
    }

    private var eyebrow: some View {
        Label {
            Text("SET YOUR FRAMING")
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.4)
        } icon: {
            Image(systemName: "viewfinder")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(GoPhotoDesign.tagText)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(GoPhotoDesign.tagBackground, in: Capsule())
    }
}

private struct ShotSizeCard: View {
    let shot: SessionShotSize
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            ShotSizeIllustration(shot: shot, isSelected: isSelected)
                .frame(width: 76)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(shot.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .lineLimit(1)
                        .fixedSize()
                    if shot.isRecommended {
                        Text("RECOMMENDED")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(GoPhotoDesign.sessionAccent, in: Capsule())
                    }
                }
                Text(shot.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                SessionChip(text: shot.cropLabel, onSelectedCard: isSelected)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SelectionIndicator(isSelected: isSelected)
        }
        .padding(14)
        .background(isSelected ? GoPhotoDesign.selectedCardBackground : Color.white,
                    in: RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(isSelected ? 0 : 0.04), radius: 10, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous))
    }
}

/// Fallback (info), re-analysis (loading) or unusable preference (error), inline under the cards.
private struct ShotSizeNoticeView: View {
    let notice: ShotSizeSelectionViewModel.Notice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            switch notice.kind {
            case .fallback:
                Image(systemName: "info.circle.fill").foregroundStyle(GoPhotoDesign.sessionAccent)
            case .loading:
                ProgressView().controlSize(.small)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange)
            }
            Text(notice.text)
                .font(.system(size: 14))
                .foregroundStyle(GoPhotoDesign.primaryText.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(notice.kind == .error ? Color.orange.opacity(0.10) : GoPhotoDesign.tagBackground.opacity(0.6),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("shotSize.notice")
    }
}
