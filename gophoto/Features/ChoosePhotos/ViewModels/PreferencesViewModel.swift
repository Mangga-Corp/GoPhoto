//
//  PreferencesViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

/// List of preferences and which one is selected. Shared by the camera popup and the editor page.
/// Every change is saved to disk (see PreferencesStorage).
final class PreferencesViewModel {
    static let shared = PreferencesViewModel()

    private let storage: PreferencesStorage
    private(set) var preferences: [Preference]
    private(set) var selectedID: UUID?

    init(storage: PreferencesStorage = PreferencesStorage()) {
        self.storage = storage
        let saved = storage.load()
        preferences = saved.preferences
        selectedID = saved.selectedID
    }

    var hasPreferences: Bool { !preferences.isEmpty }
    var canDelete: Bool { preferences.count > 1 }
    let cannotDeleteMessage = "You can’t delete this preference. At least one preference is required as the reference for your photos."

    func isSelected(at index: Int) -> Bool { preferences[index].id == selectedID }

    func preference(id: UUID) -> Preference? { preferences.first { $0.id == id } }

    func select(at index: Int) {
        guard preferences.indices.contains(index) else { return }
        selectedID = preferences[index].id
        persist()
    }

//    /// Returns an error message, or nil when added.
//    func add(name: String) -> String? {
//        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
//        guard !trimmed.isEmpty else { return "Enter a name." }
//        guard !preferences.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
//            return "That preference already exists."
//        }
//        preferences.append(Preference(name: trimmed))
//        persist()
//        return nil
//    }

    func nameError(for name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a name."}
        guard !preferences.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return "That preference already exist."
        }
        return nil
    }

    @discardableResult
    func add(name: String, photos: [PhotoItem]) -> String? {
        if let error = nameError(for: name) { return error }
        let preference = Preference(name: name.trimmingCharacters(in: .whitespacesAndNewlines), photos: photos)
        preferences.append(preference)
        selectedID = preference.id
        persist()
        return nil
    }

    /// Returns an error message, or nil when renamed.
    func rename(id: UUID, to name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a name." }
        guard !preferences.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return "That preference already exists."
        }
        guard let index = preferences.firstIndex(where: { $0.id == id }) else { return nil }
        preferences[index].name = trimmed
        persist()
        return nil
    }

    func updatePhotos(_ photos: [PhotoItem], for id: UUID) {
        guard let index = preferences.firstIndex(where: { $0.id == id }) else { return }
        preferences[index].photos = photos
        persist()
    }

    /// Creates the first preference from the photos picked during onboarding and selects it.
    func addFirstPreference(name: String, photos: [PhotoItem]) {
        let preference = Preference(name: name, photos: photos)
        preferences.append(preference)
        selectedID = preference.id
        persist()
    }

    /// Returns false when it is the last preference (never deletable).
    @discardableResult
    func delete(id: UUID) -> Bool {
        guard canDelete, let index = preferences.firstIndex(where: { $0.id == id }) else { return false }
        preferences.remove(at: index)
        if selectedID == id { selectedID = preferences.first?.id }
        persist()
        return true
    }

    private func persist() { storage.save(preferences, selectedID: selectedID) }
}
