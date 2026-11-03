//
//  PreferencesViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation
import Observation

/// A preference name that was not accepted (empty, or already used).
struct PreferenceNameError: Error, Equatable {
    let message: String
}

/// The saved preferences and the last one used to start a camera session.
/// Every change is saved to disk (see PreferencesStorage).
///
/// Which preference and shot size the camera uses right now is session state and lives in
/// `PhotoSessionStore`, not here.
@Observable
final class PreferencesViewModel {
    static let shared = PreferencesViewModel()

    /// Shot size key of older versions (the popover's switch, saved across launches). Shot size
    /// is now chosen per session and never saved, so the stale value is removed at launch.
    private static let legacyShotSizeKey = "presetShotSize"

    @ObservationIgnored private let storage: PreferencesStorage
    private(set) var preferences: [Preference]
    /// The preference used to start the most recent successful camera session. Saved as
    /// `selectedID` in `index.json` (same field as before, so existing installs keep it).
    /// Changed only by `recordLastSelected(id:)` (a session started) and by deleting that
    /// preference; never points at a preference that does not exist.
    private(set) var lastSelectedID: UUID?

    init(storage: PreferencesStorage = PreferencesStorage(), defaults: UserDefaults = .standard) {
        self.storage = storage
        let saved = storage.load()
        preferences = saved.preferences
        // A saved ID whose preference is gone is dropped (written out with the next save).
        lastSelectedID = saved.selectedID.flatMap { id in
            saved.preferences.contains { $0.id == id } ? id : nil
        }
        defaults.removeObject(forKey: Self.legacyShotSizeKey)
        // Presets saved before the AI existed (or with an older result) are analysed now.
        for preference in preferences where preference.analysis?.isCurrent != true {
            reanalyze(id: preference.id)
        }
    }

    var hasPreferences: Bool { !preferences.isEmpty }
    var canDelete: Bool { preferences.count > 1 }
    let cannotDeleteMessage = "You can’t delete this preference. At least one preference is required as the reference for your photos."

    func preference(id: UUID) -> Preference? { preferences.first { $0.id == id } }

    var lastSelectedPreference: Preference? { lastSelectedID.flatMap { preference(id: $0) } }

    /// The preference to preselect when a new session is configured: the last one used when it
    /// still exists, else the first saved preference with photos, else the first one. Nil only
    /// when nothing is saved.
    var resolvedLastSelectedID: UUID? {
        if let preference = lastSelectedPreference { return preference.id }
        return (preferences.first { !$0.photos.isEmpty } ?? preferences.first)?.id
    }

    /// Remembers the preference a camera session was just started with. Called by
    /// `PhotoSessionStore` only after the session was created; unknown IDs are ignored.
    func recordLastSelected(id: UUID) {
        guard preference(id: id) != nil, lastSelectedID != id else { return }
        lastSelectedID = id
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

    /// Saves a new preference and returns its ID. It does not become the last selected
    /// preference here: that happens when a camera session is started with it.
    @discardableResult
    func add(name: String, photos: [PhotoItem]) -> Result<UUID, PreferenceNameError> {
        if let error = nameError(for: name) { return .failure(PreferenceNameError(message: error)) }
        let preference = Preference(name: name.trimmingCharacters(in: .whitespacesAndNewlines), photos: photos)
        preferences.append(preference)
        persist()
        return .success(preference.id)
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
    @ObservationIgnored private var analysisChain: Task<Void, Never>?
    @ObservationIgnored private var analysisTokens: [UUID: Int] = [:]
    /// Latest analysis run per preset, kept in memory for the results screen (not saved).
    @ObservationIgnored private var sessions: [UUID: AnalysisSession] = [:]
    /// Observed, so screens can show which presets are being analysed.
    private var analyzingIDs: Set<UUID> = []
    /// The newest analysis task per preset, so a screen can wait for one already running.
    @ObservationIgnored private var analysisTasks: [UUID: Task<Void, Never>] = [:]

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
            self.analysisRunCount += 1
            #if DEBUG
            // UI tests only (`-GoPhotoFakeAnalysis <mode>`): a stand-in result instead of Vision.
            let analysis: PresetAnalysis?
            if let fake = await DebugFixtures.fakeAnalysis(for: photos) {
                analysis = fake
            } else {
                analysis = await session.analyze(photos)
            }
            #else
            let analysis = await session.analyze(photos)
            #endif
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

    /// Returns false when it is the last preference (never deletable).
    /// Deleting the last selected preference clears it (`resolvedLastSelectedID` then falls back);
    /// another preference is not recorded as "used". A session running with the deleted
    /// preference is invalidated by `PhotoSessionStore`, never switched to another preference.
    ///
    /// `allowingLast`: the camera's popover keeps at least one preference (the camera has no way
    /// to create one from an empty state). Preference Selection passes true: it shows an empty
    /// state with Add New Preference, and nothing else needs a saved preference to exist.
    @discardableResult
    func delete(id: UUID, allowingLast: Bool = false) -> Bool {
        guard allowingLast || canDelete,
              let index = preferences.firstIndex(where: { $0.id == id }) else { return false }
        preferences.remove(at: index)
        if lastSelectedID == id { lastSelectedID = nil }
        persist()
        return true
    }

    /// Saves requested since launch. Diagnostics only (debug UI tests check that selecting a
    /// card writes nothing); not saved.
    private(set) var persistCount = 0
    /// Analysis runs started since launch. Diagnostics only (debug UI tests check that a retry
    /// really runs the analysis again); not saved.
    private(set) var analysisRunCount = 0

    private func persist() {
        persistCount += 1
        storage.save(preferences, selectedID: lastSelectedID)
    }
}
