//
//  PreferenceSelectionViewModel.swift
//  gophoto
//
//  State of the Preference Selection screen: the draft card selection only. Saved preferences
//  and management operations stay in `PreferencesViewModel`; session validity comes from
//  `PhotoSessionStore`. Selecting a card never writes anything to disk.
//

import Foundation
import Observation

@Observable
final class PreferenceSelectionViewModel {
    @ObservationIgnored let preferences: PreferencesViewModel
    @ObservationIgnored let sessions: PhotoSessionStore

    /// The card currently selected. Temporary: not saved, not the last used preference.
    private(set) var draftSelectedID: UUID?
    /// The user tapped a card, so an empty draft is not filled automatically any more.
    @ObservationIgnored private var userHasChosen = false

    init(preferences: PreferencesViewModel = .shared, sessions: PhotoSessionStore = .shared) {
        self.preferences = preferences
        self.sessions = sessions
    }

    // MARK: Data shown

    var cards: [PreferenceCardModel] {
        preferences.preferences.map { preference in
            PreferenceCardModel(preference: preference,
                                availability: sessions.sessionAvailability(preferenceID: preference.id),
                                isAnalyzing: preferences.isAnalyzing(preference.id),
                                isLastUsed: preference.id == preferences.lastSelectedID)
        }
    }

    var savedCountText: String { PreferenceDraftRules.savedCountText(preferences.preferences.count) }
    var hasPreferences: Bool { preferences.hasPreferences }

    /// Changes whenever the draft has to be re-checked (list, names, analyses, analysing state).
    var reconcileKey: [String] {
        preferences.preferences.map { preference in
            let available = (try? sessions.sessionAvailability(preferenceID: preference.id).get()) != nil
            return "\(preference.id.uuidString)|\(available)"
        }
    }

    // MARK: Draft selection

    /// Called on appear and whenever `reconcileKey` changes.
    func reconcile() {
        let next = PreferenceDraftRules.reconcile(draft: draftSelectedID, userHasChosen: userHasChosen,
                                                  preferred: sessions.initialPreferenceID,
                                                  orderedIDs: orderedIDs, isAvailable: isAvailable)
        if next != draftSelectedID { draftSelectedID = next }
    }

    /// A card tap: changes the draft only (never `recordLastSelected`, never saved).
    func select(_ id: UUID) {
        guard isAvailable(id), draftSelectedID != id else { return }
        userHasChosen = true
        draftSelectedID = id
    }

    /// The preference to hand to Shot Size Selection, re-validated now; nil disables Continue.
    var continueTarget: UUID? {
        PreferenceDraftRules.continueTarget(draft: draftSelectedID, orderedIDs: orderedIDs, isAvailable: isAvailable)
    }

    /// A preference was just created through Add New Preference. It becomes the draft when it can
    /// start a session; otherwise the current selection is left alone (a valid choice is never
    /// cleared because the new preference can't be used yet).
    func selectCreated(_ id: UUID) {
        guard preferences.preference(id: id) != nil, isAvailable(id) else { return }
        userHasChosen = true
        draftSelectedID = id
    }

    /// Applies a one-time handoff without falling back to another preference if it is invalid.
    func selectHandoff(_ id: UUID?) -> String? {
        guard let id else {
            userHasChosen = true
            draftSelectedID = nil
            return "The newly created preference could not be identified. Select a preference to continue."
        }
        guard preferences.preference(id: id) != nil else {
            userHasChosen = true
            draftSelectedID = nil
            return "The newly created preference could not be found. Select a preference to continue."
        }
        guard isAvailable(id) else {
            userHasChosen = true
            draftSelectedID = nil
            return "The newly created preference is not available yet. Select a preference to continue."
        }
        selectCreated(id)
        return nil
    }

    private var orderedIDs: [UUID] { preferences.preferences.map(\.id) }

    private func isAvailable(_ id: UUID) -> Bool {
        if case .success = sessions.sessionAvailability(preferenceID: id) { return true }
        return false
    }

    // MARK: Management (existing operations)

    /// Returns the existing validation error, or nil when renamed.
    func rename(_ id: UUID, to name: String) -> String? { preferences.rename(id: id, to: name) }

    /// Existing delete, including the last preference (this screen then shows its empty state).
    /// The last used ID is cleared by `PreferencesViewModel.delete`; the draft is reconciled here,
    /// so a deleted ID never stays selected or reaches Continue.
    @discardableResult
    func delete(_ id: UUID) -> Bool {
        let deleted = preferences.delete(id: id, allowingLast: true)
        if deleted { reconcile() }
        return deleted
    }
}
