//
//  PreferenceDraftRules.swift
//  gophoto
//
//  Which preference card is selected on Preference Selection. The selection is a temporary draft:
//  nothing here is saved. The last used preference is only recorded when a session starts.
//

import Foundation

nonisolated enum PreferenceDraftRules {

    /// The card selected when the screen opens: the last used preference when it can start a
    /// session, otherwise the first one in list order that can. Nil when none can.
    static func initialSelection(preferred: UUID?, orderedIDs: [UUID],
                                 isAvailable: (UUID) -> Bool) -> UUID? {
        if let preferred, orderedIDs.contains(preferred), isAvailable(preferred) { return preferred }
        return orderedIDs.first(where: isAvailable)
    }

    /// The draft after the saved preferences changed (deleted, renamed, re-analysed, added).
    /// - Draft deleted: replaced by the initial selection (never kept as a stale ID).
    /// - Draft can no longer start a session: cleared, so Continue is disabled and the card shows why.
    /// - No draft yet and the user hasn't picked one: the initial selection (e.g. an analysis finished).
    static func reconcile(draft: UUID?, userHasChosen: Bool, preferred: UUID?, orderedIDs: [UUID],
                          isAvailable: (UUID) -> Bool) -> UUID? {
        if let draft {
            guard orderedIDs.contains(draft) else {
                return initialSelection(preferred: preferred, orderedIDs: orderedIDs, isAvailable: isAvailable)
            }
            return isAvailable(draft) ? draft : nil
        }
        return userHasChosen ? nil
            : initialSelection(preferred: preferred, orderedIDs: orderedIDs, isAvailable: isAvailable)
    }

    /// The preference Continue hands to Shot Size Selection, or nil when it must stay disabled.
    static func continueTarget(draft: UUID?, orderedIDs: [UUID], isAvailable: (UUID) -> Bool) -> UUID? {
        guard let draft, orderedIDs.contains(draft), isAvailable(draft) else { return nil }
        return draft
    }

    /// "1 Saved Profile", "3 Saved Profiles".
    static func savedCountText(_ count: Int) -> String {
        count == 1 ? "1 Saved Profile" : "\(count) Saved Profiles"
    }
}
