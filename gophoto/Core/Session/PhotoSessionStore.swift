//
//  PhotoSessionStore.swift
//  gophoto
//
//  The active photography session. Owns only temporary state (the current
//  `PhotoSessionConfiguration`); saved preferences and the last selected preference ID stay in
//  `PreferencesViewModel`, which this store asks to record the ID once a session starts.
//

import Foundation
import Observation

/// Why a session that was started can no longer guide the camera.
nonisolated enum PhotoSessionInvalidation: Equatable, Sendable {
    /// Its preference was deleted.
    case preferenceDeleted
    /// Its preference was analysed again and no longer has the session's effective shot variant.
    case shotVariantUnavailable
}

nonisolated enum PhotoSessionStatus: Equatable, Sendable {
    /// No session has been started (or the last one ended).
    case none
    case active(PhotoSessionConfiguration)
    /// Started, but no longer valid. The camera must not guide with it, and no other preference
    /// is put in its place: a new session has to be started.
    case invalidated(PhotoSessionConfiguration, PhotoSessionInvalidation)
}

@Observable
final class PhotoSessionStore {
    static let shared = PhotoSessionStore()

    @ObservationIgnored private let preferences: PreferencesViewModel

    /// The last session started, until `endSession()` or the next `startSession`. Use `status`
    /// or `activeSession`: this may point at a deleted preference.
    private(set) var current: PhotoSessionConfiguration?
    /// Why the last `startSession` failed, for future UI. Cleared by the next successful start.
    private(set) var lastStartError: PhotoSessionError?

    init(preferences: PreferencesViewModel = .shared) {
        self.preferences = preferences
    }

    /// Re-checked against the saved preferences on every read (observed, so views update when
    /// the session's preference is deleted or re-analysed).
    var status: PhotoSessionStatus {
        guard let current else { return .none }
        guard let preference = preferences.preference(id: current.preferenceID) else {
            return .invalidated(current, .preferenceDeleted)
        }
        guard preference.analysis?.hasGuide(for: current.effectiveShotSize) == true else {
            return .invalidated(current, .shotVariantUnavailable)
        }
        return .active(current)
    }

    /// The session the camera guides with, or nil when there is none or it was invalidated.
    var activeSession: PhotoSessionConfiguration? {
        if case .active(let configuration) = status { return configuration }
        return nil
    }

    /// Preselection for configuring a new session (last used preference, or a safe fallback).
    var initialPreferenceID: UUID? { preferences.resolvedLastSelectedID }

    /// Validates a session without starting it (no side effects).
    func configuration(preferenceID: UUID, shotSize: SessionShotSize) -> Result<PhotoSessionConfiguration, PhotoSessionError> {
        guard let preference = preferences.preference(id: preferenceID) else { return .failure(.preferenceNotFound) }
        return PhotoSessionConfiguration.resolve(preferenceID: preferenceID, analysis: preference.analysis,
                                                 requestedShotSize: shotSize)
    }

    /// Whether a session could be started with this preference right now (no side effects).
    /// Independent of the shot size: when the requested variant is missing the analysis default
    /// is used, so resolution succeeds for every shot size or for none.
    func sessionAvailability(preferenceID: UUID) -> Result<Void, PhotoSessionError> {
        configuration(preferenceID: preferenceID, shotSize: .initialSelection).map { _ in () }
    }

    /// Starts a new session (always a new `id`) and, only when it was created, records its
    /// preference as the last selected one. On failure nothing changes except `lastStartError`.
    @discardableResult
    func startSession(preferenceID: UUID, shotSize: SessionShotSize) -> Result<PhotoSessionConfiguration, PhotoSessionError> {
        let result = configuration(preferenceID: preferenceID, shotSize: shotSize)
        switch result {
        case .success(let configuration):
            startCount += 1
            current = configuration
            lastStartError = nil
            preferences.recordLastSelected(id: configuration.preferenceID)
        case .failure(let error):
            lastStartError = error
        }
        return result
    }

    /// Ends the current session (the camera was closed), so it is never reused for the next one.
    /// Ending when there is none does nothing.
    func endSession() {
        endCount += 1
        current = nil
    }

    /// Diagnostics only (debug UI tests check one start per tap and one end per close).
    private(set) var startCount = 0
    private(set) var endCount = 0
}
