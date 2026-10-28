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
    /// Shot size picked in the preset popover (`PresetAnalysis.ShotSize.rawValue`: "full" /
    /// "threeQuarter" / "half" / "quarter"), or nil for the preset's default. Saved across launches.
    private(set) var framing: String? = UserDefaults.standard.string(forKey: PreferencesViewModel.framingKey)
    private static let framingKey = "presetShotSize"

    func setFraming(_ framing: String?) {
        self.framing = framing
        UserDefaults.standard.set(framing, forKey: Self.framingKey)
    }

    /// The shot size the camera uses for a preset: the picked one when the preset has photos of
    /// it, else the size with the most photos. Older analyses: the picked or majority framing.
    func effectiveFraming(for preference: Preference?) -> String? {
        guard let analysis = preference?.analysis else { return framing }
        let shots = analysis.availableShots
        if shots.isEmpty { return framing ?? analysis.framing }
        if let framing, shots.contains(where: { $0.rawValue == framing }) { return framing }
        return analysis.defaultShot?.rawValue
    }

    init(storage: PreferencesStorage = PreferencesStorage()) {
        self.storage = storage
        let saved = storage.load()
        preferences = saved.preferences
        selectedID = saved.selectedID
        // Presets saved before the AI existed (or with an older result) are analysed now.
        for preference in preferences where preference.analysis?.isCurrent != true {
            reanalyze(id: preference.id)
        }
    }

    var hasPreferences: Bool { !preferences.isEmpty }
    var canDelete: Bool { preferences.count > 1 }
    let cannotDeleteMessage = "You can’t delete this preference. At least one preference is required as the reference for your photos."

    func isSelected(at index: Int) -> Bool { preferences[index].id == selectedID }

    func preference(id: UUID) -> Preference? { preferences.first { $0.id == id } }

    var selectedPreference: Preference? { selectedID.flatMap { preference(id: $0) } }

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
        reanalyze(id: id)   // PRD 1.3: adding or removing photos analyses the preset again
    }

    // MARK: AI analysis

    /// The last analysis started; the next one waits for it so only one runs at a time.
    private var analysisChain: Task<Void, Never>?
    private var analysisTokens: [UUID: Int] = [:]
    /// Latest analysis run per preset, kept in memory for the results screen (not saved).
    private var sessions: [UUID: AnalysisSession] = [:]
    private var analyzingIDs: Set<UUID> = []
    /// The newest analysis task per preset, so a screen can wait for one already running.
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    /// The analysis of this preset that is still running (e.g. started by an edit), or nil.
    func runningAnalysis(for id: UUID) -> Task<Void, Never>? {
        analyzingIDs.contains(id) ? analysisTasks[id] : nil
    }

    func session(for id: UUID) -> AnalysisSession? { sessions[id] }
    func isAnalyzing(_ id: UUID) -> Bool { analyzingIDs.contains(id) }

    /// Analyses a preset's photos and saves the result with the preset.
    /// Only the newest request per preset is saved. Await `value` to know when it is done.
    @discardableResult
    func reanalyze(id: UUID) -> Task<Void, Never>? {
        guard let photos = preference(id: id)?.photos, !photos.isEmpty else { return nil }
        let token = (analysisTokens[id] ?? 0) + 1
        analysisTokens[id] = token
        let session = AnalysisSession()
        sessions[id] = session
        analyzingIDs.insert(id)
        let previous = analysisChain
        let task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            guard self.analysisTokens[id] == token else { return }
            let analysis = await session.analyze(photos)
            guard self.analysisTokens[id] == token else { return }
            self.analyzingIDs.remove(id)
            if let analysis { self.setAnalysis(analysis, for: id) }
        }
        analysisChain = task
        analysisTasks[id] = task
        return task
    }

    func setAnalysis(_ analysis: PresetAnalysis, for id: UUID) {
        guard let index = preferences.firstIndex(where: { $0.id == id }) else { return }
        preferences[index].analysis = analysis
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
