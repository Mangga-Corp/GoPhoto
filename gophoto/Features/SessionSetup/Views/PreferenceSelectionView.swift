//
//  PreferenceSelectionView.swift
//  gophoto
//
//  "What would you like to shoot today?": pick the preference for the next session. A card tap
//  only changes the draft selection; Continue hands the preference ID on without starting a
//  session or saving anything. Long-press a card to rename, edit its photos or delete it.
//

import SwiftUI

struct PreferenceSelectionView: View {
    /// Carries the onboarding preference ID through this route; selection behavior is unchanged.
    let handoffPreferenceID: UUID?
    let hasPreferenceHandoff: Bool
    let selection: PreferenceSelectionViewModel
    /// Continue, with a preference that exists and can start a session.
    let onContinue: (UUID) -> PhotoSessionError?
    let onAddNew: () -> Void
    let onHandoffConsumed: (() -> Void)?

    @State private var anchor = PresentationAnchor()
    @State private var editorPresenter: PreferenceEditorPresenter?
    @State private var renameTarget: PreferenceCardModel?
    @State private var renameText = ""
    @State private var deleteTarget: PreferenceCardModel?
    @State private var errorMessage: String?
    @State private var didApplyHandoff = false

    var body: some View {
        let cards = selection.cards
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                HStack(alignment: .center) {
                    Text("Your Preferences")
                        .font(GoPhotoDesign.sectionTitle)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                    Spacer(minLength: 12)
                    Text(selection.savedCountText)
                        .goPhotoTag()
                }
                .padding(.top, 28)

                VStack(spacing: 14) {
                    if cards.isEmpty {
                        emptyState
                    }
                    ForEach(cards) { card in
                        cardView(card)
                    }
                    AddPreferenceCard(action: onAddNew)
                        .accessibilityIdentifier("preferenceSelection.addNew")
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, GoPhotoDesign.sessionMargin)
        }
        .scrollIndicators(.hidden)
        .appPatternBackground()
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue", isEnabled: selection.continueTarget != nil) {
                // Re-validated at the tap: never hands on a deleted or unusable preference.
                if let id = selection.continueTarget, let error = onContinue(id) {
                    errorMessage = error.message
                }
            }
            .accessibilityIdentifier("preferenceSelection.continue")
            .accessibilityHint(selection.continueTarget == nil ? "Select a preference first" : "Opens the camera")
        }
        .background { PresentationAnchorView(anchor: anchor) }
        .onAppear {
            guard !didApplyHandoff else { return }
            didApplyHandoff = true
            if hasPreferenceHandoff {
                errorMessage = selection.selectHandoff(handoffPreferenceID)
                onHandoffConsumed?()
            } else {
                selection.reconcile()
            }
        }
        .onChange(of: selection.reconcileKey) { selection.reconcile() }
        .alert("Rename Preference", isPresented: isPresented($renameTarget), presenting: renameTarget) { card in
            TextField("Name", text: $renameText)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveRename(card) }
        } message: { _ in
            Text("Give this preference a new name.")
        }
        .alert(deleteTarget.map { "Delete “\($0.name)”?" } ?? "", isPresented: isPresented($deleteTarget),
               presenting: deleteTarget) { card in
            Button("Delete", role: .destructive) { selection.delete(card.id) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its photos will be removed. This can’t be undone.")
        }
        .alert("Something went wrong", isPresented: isPresented($errorMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What would you like to shoot today?")
                .font(GoPhotoDesign.pageTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Choose a photography preference for your next session.")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 36)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 30))
                .foregroundStyle(GoPhotoDesign.primary)
            Text("No preferences yet")
                .font(GoPhotoDesign.cardTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
            Text("Add reference portraits below to create your first photography preference.")
                .font(GoPhotoDesign.secondaryBody)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .goPhotoCard()
    }

    private func cardView(_ card: PreferenceCardModel) -> some View {
        let isSelected = selection.draftSelectedID == card.id
        return PreferenceSelectionCard(card: card, isSelected: isSelected)
            .onTapGesture { selection.select(card.id) }
            .contextMenu { managementActions(card) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(card.isAvailable ? "Selects this preference" : card.summary)
            .accessibilityIdentifier("preferenceCard.\(card.name)")
            .accessibilityAction(named: "Rename") { startRename(card) }
            .accessibilityAction(named: "Edit Photos") { editPhotos(card) }
            .accessibilityAction(named: "Delete") { confirmDelete(card) }
            // Visible way into the same actions (long-press still works). Outside the card's
            // combined element so its tap opens the menu instead of selecting the card.
            .overlay(alignment: .topTrailing) {
                Menu { managementActions(card) } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                        .frame(width: 44, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More actions for \(card.name)")
                .accessibilityIdentifier("preferenceMenu.\(card.name)")
                .padding(.top, 2)
                .padding(.trailing, 4)
            }
    }

    @ViewBuilder private func managementActions(_ card: PreferenceCardModel) -> some View {
        Button("About This Style", systemImage: "info.circle") { showAbout(card) }
            .disabled(styleSummary(for: card.id) == nil)
            .accessibilityAction(named: "About This Style") { showAbout(card) }
        Button("Rename", systemImage: "pencil") { startRename(card) }
        Button("Edit Photos", systemImage: "photo.on.rectangle") { editPhotos(card) }
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete(card) }
    }

    // MARK: Management (existing operations)

    private func startRename(_ card: PreferenceCardModel) {
        renameText = card.name
        renameTarget = card
    }

    /// Existing rename and its validation (empty or duplicate names are refused).
    private func saveRename(_ card: PreferenceCardModel) {
        guard let error = selection.rename(card.id, to: renameText) else { return }
        // Shown after the rename alert has gone (two alerts can't be presented at once).
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            errorMessage = error
        }
    }

    private func editPhotos(_ card: PreferenceCardModel) {
        guard let presenter = anchor.presenter else { return }
        let editor = PreferenceEditorPresenter(preferences: selection.preferences)
        editorPresenter = editor   // kept alive while the editor is open
        editor.presentEditor(for: card.id, from: presenter) { _ in editorPresenter = nil }
    }

    private func showAbout(_ card: PreferenceCardModel) {
        guard let presenter = anchor.presenter,
              let summary = styleSummary(for: card.id) else { return }
        let styleCard = StyleCardViewController(summary: summary, buttonTitle: "Done")
        styleCard.modalPresentationStyle = .fullScreen
        styleCard.onDone = { [weak styleCard] in styleCard?.dismiss(animated: true)}
        presenter.present(styleCard, animated: true)
    }

    private func styleSummary(for id: UUID) -> StyleSummary? {
        guard let preference = selection.preferences.preference(id: id),
              preference.analysis?.usability == .usable else { return nil }
        return StyleSummary(analysis: preference.analysis, photos: preference.photos)
    }

    private func confirmDelete(_ card: PreferenceCardModel) {
        deleteTarget = card
    }

    private func isPresented<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}
