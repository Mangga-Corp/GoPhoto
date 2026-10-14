//
//  PreferencesViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

/// List of preferences and which one is selected. Shared by the camera popup and the editor page.
final class PreferencesViewModel {
    static let shared = PreferencesViewModel()

    private(set) var preferences: [Preference] = [Preference(name: "Mountain"), Preference(name: "Town")]
    private(set) var selectedID: UUID?

    func isSelected(at index: Int) -> Bool { preferences[index].id == selectedID }

    func preference(id: UUID) -> Preference? { preferences.first { $0.id == id } }

    func select(at index: Int) {
        guard preferences.indices.contains(index) else { return }
        selectedID = preferences[index].id
    }

    /// Returns an error message, or nil when added.
    func add(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a name." }
        guard !preferences.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return "That preference already exists."
        }
        preferences.append(Preference(name: trimmed))
        return nil
    }

    func updatePhotos(_ photos: [PhotoItem], for id: UUID) {
        guard let index = preferences.firstIndex(where: { $0.id == id }) else { return }
        preferences[index].photos = photos
    }
}
