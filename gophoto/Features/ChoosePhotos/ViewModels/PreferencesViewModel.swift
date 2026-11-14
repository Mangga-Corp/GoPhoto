//
//  PreferencesViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation
import Observation
import os

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
    static let pendingOnboardingPreferenceIDKey = "pendingOnboardingAnalysisPreferenceID"

    /// Shot size key of older versions (the popover's switch, saved across launches). Shot size
    /// is now chosen per session and never saved, so the stale value is removed at launch.
    private static let legacyShotSizeKey = "presetShotSize"

    @ObservationIgnored private let storage: PreferencesStorage
    @ObservationIgnored private let logger = Logger(subsystem: "co.mango.gophoto", category: "preferences.analysis")
    private(set) var preferences: [Preference]
    private var isSavingNewPreference = false
    @ObservationIgnored private var updatingPhotoIDs: Set<UUID> = []
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
        let pendingOnboardingID = defaults.string(forKey: Self.pendingOnboardingPreferenceIDKey)
            .flatMap { UUID(uuidString: $0) }
        // The onboarding flow starts this preference explicitly; startup must not start a
        // competing run before that flow can join it.
        for preference in preferences
        where preference.analysis?.isCurrent != true && preference.id != pendingOnboardingID {
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

    /// Commits a new preference and its source images before publishing it in memory. Used by
    /// first-time setup so a successful name submission is recoverable after app interruption.
    func addPersisted(
        id: UUID = UUID(),
        name: String,
        photos: [PhotoItem],
        completion: @escaping (Result<UUID, PreferenceNameError>) -> Void
    ) {
        guard !isSavingNewPreference else {
            completion(.failure(PreferenceNameError(message: "Saving is already in progress. Please wait.")))
            return
        }
        if let error = nameError(for: name) {
            completion(.failure(PreferenceNameError(message: error)))
            return
        }
        guard preference(id: id) == nil else {
            completion(.failure(PreferenceNameError(message: "This preference has already been saved.")))
            return
        }

        var seenPhotoIDs = Set<UUID>()
        var seenAssetIDs = Set<String>()
        let validPhotos = photos.filter { photo in
            guard seenPhotoIDs.insert(photo.id).inserted else { return false }
            guard let assetID = photo.sourceAssetIdentifier else { return true }
            return seenAssetIDs.insert(assetID).inserted
        }
        guard validPhotos.count >= ChoosePhotosViewModel.minPhotos else {
            completion(.failure(PreferenceNameError(
                message: "Select at least \(ChoosePhotosViewModel.minPhotos) valid photos before continuing."
            )))
            return
        }

        let preference = Preference(
            id: id,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            photos: validPhotos
        )
        let updatedPreferences = preferences + [preference]
        isSavingNewPreference = true
        storage.save(updatedPreferences, selectedID: lastSelectedID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.storage.loadPreference(id: preference.id) { loadResult in
                        DispatchQueue.main.async {
                            switch loadResult {
                            case .success(let persistedPreference)
                                where persistedPreference.photos.count == validPhotos.count:
                                self.preferences.append(persistedPreference)
                                self.isSavingNewPreference = false
                                self.persistCount += 1
                                completion(.success(persistedPreference.id))
                            case .success, .failure:
                                self.rollbackFailedPreferenceSave(completion: completion)
                            }
                        }
                    }
                case .failure:
                    self.isSavingNewPreference = false
                    completion(.failure(PreferenceNameError(
                        message: "Couldn't save the preference and its photos. Check available storage and try again."
                    )))
                }
            }
        }
    }

    /// Saves a custom preference (subject placement + camera angle, no photos) and publishes it
    /// once it is on disk. Its name is the combination's suggested name, numbered when that name
    /// is already used ("Heroic Thirds 2"), so creating it never asks the user for a name.
    func addCustomPersisted(
        style: CustomPreferenceStyle,
        completion: @escaping (Result<UUID, PreferenceNameError>) -> Void
    ) {
        guard !isSavingNewPreference else {
            completion(.failure(PreferenceNameError(message: "Saving is already in progress. Please wait.")))
            return
        }
        guard !preferences.contains(where: { $0.customStyle == style }) else {
            completion(.failure(PreferenceNameError(
                message: "This combination has already been created. You can only have one of each combination."
            )))
            return
        }
        let name = CustomPreferenceNaming.uniqueName(style.suggestedName, existing: preferences.map(\.name))
        let preference = Preference(name: name, customStyle: style)
        isSavingNewPreference = true
        storage.save(preferences + [preference], selectedID: lastSelectedID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isSavingNewPreference = false
                switch result {
                case .success:
                    self.preferences.append(preference)
                    self.persistCount += 1
                    completion(.success(preference.id))
                case .failure:
                    completion(.failure(PreferenceNameError(
                        message: "Couldn't save the custom preference. Check available storage and try again."
                    )))
                }
            }
        }
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

    /// Custom preferences have no photos: they are left unchanged.
    func updatePhotos(_ photos: [PhotoItem], for id: UUID) {
        guard let index = preferences.firstIndex(where: { $0.id == id }),
              !preferences[index].isCustom else { return }
        preferences[index].photos = photos
        persist()
        reanalyze(id: id)   // PRD 1.3: adding or removing photos analyses the preset again
    }

    /// Loads the exact preference from disk, including its photos in persisted order.
    func loadPersistedPreference(
        id: UUID,
        completion: @escaping (Result<Preference, Error>) -> Void
    ) {
        storage.loadPreference(id: id) { result in
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Adds photos to an existing preference atomically. The in-memory preference is only
    /// replaced after its updated photo collection has been written and read back successfully.
    func addPhotosPersisted(
        _ photos: [PhotoItem],
        to id: UUID,
        completion: @escaping (Result<Preference, PreferenceNameError>) -> Void
    ) {
        guard !updatingPhotoIDs.contains(id) else {
            completion(.failure(PreferenceNameError(message: "Photos are already being saved. Please wait.")))
            return
        }
        guard let index = preferences.firstIndex(where: { $0.id == id }) else {
            completion(.failure(PreferenceNameError(message: "The saved preference could not be found.")))
            return
        }
        guard !preferences[index].isCustom else {
            completion(.failure(Self.customPhotosError))
            return
        }

        let current = preferences[index]
        let updatedPhotos = mergedPhotos(current.photos, photos)
        guard updatedPhotos.count <= ChoosePhotosViewModel.maxPhotos else {
            completion(.failure(PreferenceNameError(message: "A preference can contain up to \(ChoosePhotosViewModel.maxPhotos) photos.")))
            return
        }
        guard updatedPhotos.map(\.id) != current.photos.map(\.id) else {
            completion(.success(current))
            return
        }

        cancelCurrentAnalysis(for: id)
        var updatedPreferences = preferences
        updatedPreferences[index].photos = updatedPhotos
        updatedPreferences[index].analysis = nil
        updatingPhotoIDs.insert(id)

        storage.save(updatedPreferences, selectedID: lastSelectedID) { [weak self] saveResult in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success = saveResult else {
                    self.updatingPhotoIDs.remove(id)
                    completion(.failure(PreferenceNameError(
                        message: "Couldn't save the additional photos. Your existing preference is unchanged. Please try again."
                    )))
                    return
                }

                self.storage.loadPreference(id: id) { loadResult in
                    DispatchQueue.main.async {
                        guard case .success(let persisted) = loadResult,
                              persisted.photos.map(\.id) == updatedPhotos.map(\.id),
                              persisted.analysis == nil,
                              let currentIndex = self.preferences.firstIndex(where: { $0.id == id }) else {
                            self.restorePreferencesAfterPhotoUpdateFailure(id: id) {
                                completion(.failure(PreferenceNameError(
                                    message: "Couldn't verify the additional photos. Your existing preference is unchanged. Please try again."
                                )))
                            }
                            return
                        }
                        self.preferences[currentIndex] = persisted
                        self.updatingPhotoIDs.remove(id)
                        self.persistCount += 1
                        completion(.success(persisted))
                    }
                }
            }
        }
    }

    /// After a "Not Enough Photos with People" warning, the user chose Continue: removes the
    /// photos the latest person check confirmed show no person from this preference's saved
    /// photo collection. Valid photos and photos that could not be checked stay, and so do the
    /// preference's ID, name and the remaining photos' identifiers. Only Poto's own copies are
    /// removed, never anything in the Photos library.
    ///
    /// Refused while another photo update of this preference is being saved, and when the
    /// check is stale (the photos changed since it ran). Like `addPhotosPersisted`, the
    /// in-memory preference changes only once the new collection was written and read back.
    func removePhotosWithoutPersonPersisted(
        from id: UUID,
        completion: @escaping (Result<Preference, PreferenceNameError>) -> Void
    ) {
        guard !updatingPhotoIDs.contains(id) else {
            completion(.failure(PreferenceNameError(message: "Photos are already being saved. Please wait.")))
            return
        }
        guard let index = preferences.firstIndex(where: { $0.id == id }) else {
            completion(.failure(PreferenceNameError(message: "The saved preference could not be found.")))
            return
        }
        let current = preferences[index]
        guard !current.isCustom else {
            completion(.failure(Self.customPhotosError))
            return
        }
        guard let validation = validationFailure(for: id),
              validation.sourcePhotos.map(\.id) == current.photos.map(\.id) else {
            completion(.failure(PreferenceNameError(
                message: "Your photos changed since they were checked. Analyze them again to check them."
            )))
            return
        }
        let removedIDs = Set(validation.invalidPhotos.map(\.id))
        guard !removedIDs.isEmpty else {
            completion(.success(current))
            return
        }
        let remainingPhotos = current.photos.filter { !removedIDs.contains($0.id) }

        cancelCurrentAnalysis(for: id)
        var updatedPreferences = preferences
        updatedPreferences[index].photos = remainingPhotos
        updatedPreferences[index].analysis = nil
        updatingPhotoIDs.insert(id)

        storage.save(updatedPreferences, selectedID: lastSelectedID) { [weak self] saveResult in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success = saveResult else {
                    self.updatingPhotoIDs.remove(id)
                    completion(.failure(PreferenceNameError(
                        message: "Couldn't remove the photos without people. Your photos are unchanged. Please try again."
                    )))
                    return
                }
                self.storage.loadPreference(id: id) { loadResult in
                    DispatchQueue.main.async {
                        guard case .success(let persisted) = loadResult,
                              persisted.photos.map(\.id) == remainingPhotos.map(\.id),
                              let currentIndex = self.preferences.firstIndex(where: { $0.id == id }) else {
                            self.restorePreferencesAfterPhotoUpdateFailure(id: id) {
                                completion(.failure(PreferenceNameError(
                                    message: "Couldn't verify the updated photos. Please try again."
                                )))
                            }
                            return
                        }
                        self.preferences[currentIndex] = persisted
                        self.updatingPhotoIDs.remove(id)
                        self.persistCount += 1
                        completion(.success(persisted))
                    }
                }
            }
        }
    }

    private func mergedPhotos(_ existing: [PhotoItem], _ additions: [PhotoItem]) -> [PhotoItem] {
        var merged = existing
        var photoIDs = Set(existing.map(\.id))
        var assetIDs = Set(existing.compactMap(\.sourceAssetIdentifier))
        for photo in additions {
            guard photoIDs.insert(photo.id).inserted else { continue }
            if let assetID = photo.sourceAssetIdentifier,
               !assetIDs.insert(assetID).inserted {
                continue
            }
            merged.append(photo)
        }
        return merged
    }

    func prepareForReanalysis(
        id: UUID,
        completion: @escaping (Result<Void, PreferenceNameError>) -> Void
    ) {
        guard let index = preferences.firstIndex(where: { $0.id == id }) else {
            completion(.failure(PreferenceNameError(message: "The saved preference could not be found.")))
            return
        }
        guard !preferences[index].isCustom else {
            completion(.failure(Self.customPhotosError))
            return
        }
        cancelCurrentAnalysis(for: id)
        guard preferences[index].analysis != nil else {
            completion(.success(()))
            return
        }

        var updatedPreferences = preferences
        updatedPreferences[index].analysis = nil
        storage.save(updatedPreferences, selectedID: lastSelectedID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                guard case .success = result,
                      let currentIndex = self.preferences.firstIndex(where: { $0.id == id }) else {
                    completion(.failure(PreferenceNameError(
                        message: "Couldn't prepare the saved preference for analysis. Please try again."
                    )))
                    return
                }
                self.preferences[currentIndex].analysis = nil
                self.persistCount += 1
                completion(.success(()))
            }
        }
    }

    private static let customPhotosError = PreferenceNameError(
        message: "Custom preferences are made from a placement and an angle, so they have no photos to edit."
    )

    private func cancelCurrentAnalysis(for id: UUID) {
        analysisTokens[id, default: 0] += 1
        analysisTasks[id] = nil
        sessions[id] = nil
        analyzingIDs.remove(id)
        // The photos are about to change: the old person check no longer applies.
        subjectValidations[id] = nil
    }

    private func restorePreferencesAfterPhotoUpdateFailure(id: UUID, completion: @escaping () -> Void) {
        storage.save(preferences, selectedID: lastSelectedID) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failure(let error) = result {
                    self.logger.error("Could not restore preference \(id) after a photo update failed: \(error.localizedDescription, privacy: .public)")
                }
                self.updatingPhotoIDs.remove(id)
                completion()
            }
        }
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
    /// The latest person check of each preset's photos (in memory only: every run checks the
    /// whole photo collection again). Observed: Photo Session Setup marks photos without a
    /// person, Preference Selection explains why a preset was not analysed.
    private var subjectValidations: [UUID: HumanSubjectValidationResult] = [:]

    /// The latest person check of this preset, when it stopped the analysis (too few photos
    /// show a person), or nil.
    func validationFailure(for id: UUID) -> HumanSubjectValidationResult? {
        guard let result = subjectValidations[id], !result.hasEnoughValidPhotos else { return nil }
        return result
    }

    /// The latest person check of this preset, passed or not.
    func subjectValidation(for id: UUID) -> HumanSubjectValidationResult? { subjectValidations[id] }

    /// The analysis of this preset that is still running (e.g. started by an edit), or nil.
    func runningAnalysis(for id: UUID) -> Task<Void, Never>? {
        analyzingIDs.contains(id) ? analysisTasks[id] : nil
    }

    func session(for id: UUID) -> AnalysisSession? { sessions[id] }
    func isAnalyzing(_ id: UUID) -> Bool { analyzingIDs.contains(id) }

    /// Analyses a preset's photos and saves the result with the preset.
    /// Only the newest request per preset is saved. Await `value` to know when it is done.
    /// Custom preferences are never analysed: their targets come from their style.
    @discardableResult
    func reanalyze(id: UUID) -> Task<Void, Never>? {
        guard let existing = preference(id: id), !existing.isCustom, !existing.photos.isEmpty else { return nil }
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
            let persistedResult: Result<Preference, Error> = await withCheckedContinuation { continuation in
                self.storage.loadPreference(id: id) { result in
                    continuation.resume(returning: result)
                }
            }
            guard case .success(let persistedPreference) = persistedResult,
                  !persistedPreference.photos.isEmpty else {
                self.logger.error("Could not analyze preference \(id): persisted photos are unavailable")
                self.analyzingIDs.remove(id)
                return
            }

            // Every saved photo is checked; only those that show a person are analysed, and
            // only when there are enough. The preference keeps all its photos.
            let validation = await HumanSubjectValidator.validate(persistedPreference.photos)
            guard self.analysisTokens[id] == token else { return }
            self.subjectValidations[id] = validation
            if validation.hasProcessingFailures {
                self.logger.error("Preference \(id): \(validation.processingFailureCount) photos could not be checked for a person")
            }
            guard validation.hasEnoughValidPhotos else {
                self.logger.notice("Preference \(id) not analysed: \(validation.validCount) of \(validation.totalInspected) photos show a person")
                self.analyzingIDs.remove(id)
                return
            }
            let photos = validation.validatedPhotos

            self.analysisRunCount += 1
            #if DEBUG
            // UI tests only (`-GoPhotoFakeAnalysis <mode>`): a stand-in result instead of Vision.
            var analysis: PresetAnalysis?
            if let fake = await DebugFixtures.fakeAnalysis(for: photos) {
                analysis = fake
            } else {
                analysis = await session.analyze(photos)
            }
            #else
            var analysis = await session.analyze(photos)
            #endif
            analysis?.analyzedPhotoIDs = photos.map(\.id.uuidString)
            guard self.analysisTokens[id] == token else { return }
            if let analysis, !(await self.setAnalysisPersisted(analysis, for: id)) {
                self.logger.error("Could not persist analysis for preference \(id)")
            }
            self.analyzingIDs.remove(id)
        }
        analysisChain = task
        analysisTasks[id] = task
        return task
    }

    private func rollbackFailedPreferenceSave(
        completion: @escaping (Result<UUID, PreferenceNameError>) -> Void
    ) {
        storage.save(preferences, selectedID: lastSelectedID) { [weak self] rollbackResult in
            DispatchQueue.main.async {
                guard let self else { return }
                if case .failure(let error) = rollbackResult {
                    self.logger.error("Could not roll back an unreadable new preference: \(error.localizedDescription, privacy: .public)")
                }
                self.isSavingNewPreference = false
                completion(.failure(PreferenceNameError(
                    message: "Couldn't verify the saved photos. Please try saving the preference again."
                )))
            }
        }
    }

    private func setAnalysisPersisted(_ analysis: PresetAnalysis, for id: UUID) async -> Bool {
        guard let index = preferences.firstIndex(where: { $0.id == id }) else { return false }
        let previousAnalysis = preferences[index].analysis
        preferences[index].analysis = analysis
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            persist { result in continuation.resume(returning: result) }
        }
        guard case .success = result else {
            if let currentIndex = preferences.firstIndex(where: { $0.id == id }),
               preferences[currentIndex].analysis == analysis {
                preferences[currentIndex].analysis = previousAnalysis
            }
            return false
        }
        return true
    }

    func setAnalysis(_ analysis: PresetAnalysis, for id: UUID) {
        guard let index = preferences.firstIndex(where: { $0.id == id }),
              !preferences[index].isCustom else { return }
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
        // Its analysis (running or queued), session and person check go with it.
        cancelCurrentAnalysis(for: id)
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

    private func persist(completion: ((Result<Void, Error>) -> Void)? = nil) {
        persistCount += 1
        storage.save(preferences, selectedID: lastSelectedID, completion: completion)
    }
}
