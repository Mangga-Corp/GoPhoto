//
//  ShotSizeSelectionViewModel.swift
//  gophoto
//
//  State of the Shot Size Selection screen: the requested shot size for the session being
//  configured. Temporary (starts at 3/4 Body every time the screen opens, never saved). The
//  effective shot variant and the fallback come from `PhotoSessionConfiguration.resolve` via
//  `PhotoSessionStore.configuration`; nothing here starts a session.
//

import Foundation
import Observation

// MARK: User-facing shot size copy (one place for both session setup screens)

extension SessionShotSize {
    var title: String {
        switch self {
        case .half: "Half Body"
        case .threeQuarter: "3/4 Body"
        case .full: "Full Body"
        }
    }

    var detail: String {
        switch self {
        case .half: "Head to waist framing"
        case .threeQuarter: "Head to mid-thigh frame"
        case .full: "Head to feet composition"
        }
    }

    var cropLabel: String {
        switch self {
        case .half: "Crop: Upper Body"
        case .threeQuarter: "Crop: Classic Editorial"
        case .full: "Crop: Full Silhouette"
        }
    }

    /// The recommended option is the initial selection.
    var isRecommended: Bool { self == .initialSelection }
}

extension PresetAnalysis.ShotSize {
    /// Same wording as the shot size cards; `.quarter` (never requestable) is a close-up.
    var displayTitle: String { SessionShotSize(analysisShotSize: self)?.title ?? "Close-up" }
}

// MARK: Screen state

@Observable
final class ShotSizeSelectionViewModel {
    enum Status {
        /// A session could start; `configuration.requiresShotSizeFallback` says whether the
        /// camera would guide with another shot size than the selected one.
        case ready(PhotoSessionConfiguration)
        /// The preference is being (re-)analysed: wait, so the session never uses stale results.
        case analyzing
        case unavailable(PhotoSessionError)
    }

    struct Notice: Equatable {
        enum Kind { case fallback, loading, error }
        let kind: Kind
        let text: String
    }

    let preferenceID: UUID
    @ObservationIgnored private let preferences: PreferencesViewModel
    @ObservationIgnored private let sessions: PhotoSessionStore

    /// The user's requested shot size. Temporary; never replaced by the fallback.
    private(set) var selectedShotSize: SessionShotSize = .initialSelection

    init(preferenceID: UUID, preferences: PreferencesViewModel = .shared, sessions: PhotoSessionStore = .shared) {
        self.preferenceID = preferenceID
        self.preferences = preferences
        self.sessions = sessions
    }

    /// A card tap: changes the requested shot size only (no session, nothing saved).
    func select(_ shot: SessionShotSize) {
        guard shot != selectedShotSize else { return }
        selectedShotSize = shot
    }

    /// Re-checked on every read against the saved preferences (observed), so a deletion or a
    /// re-analysis while the screen is open is reflected at once.
    var status: Status {
        guard preferences.preference(id: preferenceID) != nil else { return .unavailable(.preferenceNotFound) }
        if preferences.isAnalyzing(preferenceID) { return .analyzing }
        switch sessions.configuration(preferenceID: preferenceID, shotSize: selectedShotSize) {
        case .success(let configuration): return .ready(configuration)
        case .failure(let error): return .unavailable(error)
        }
    }

    var canStartShooting: Bool {
        if case .ready = status { return true }
        return false
    }

    var notice: Notice? {
        switch status {
        case .ready(let configuration):
            guard configuration.requiresShotSizeFallback else { return nil }
            return Notice(kind: .fallback, text:
                "This preference doesn't include \(configuration.requestedShotSize.title) framing. "
                + "We'll use its \(configuration.effectiveShotSize.displayTitle) framing instead.")
        case .analyzing:
            return Notice(kind: .loading, text:
                "Updating this preference's analysis. You can start shooting when it's done.")
        case .unavailable(.preferenceNotFound):
            return Notice(kind: .error, text: "This preference was deleted. Go back to choose another one.")
        case .unavailable(.analysisFailed):
            return Notice(kind: .error, text:
                "We couldn't analyze this preference's photos. Go back and edit its photos, or choose another preference.")
        case .unavailable(.analysisUnavailable):
            return Notice(kind: .error, text:
                "This preference's analysis is unavailable. Go back and edit its photos, or choose another preference.")
        case .unavailable(.noShotVariant):
            return Notice(kind: .error, text:
                "We couldn't read the framing in this preference's photos, so it can't guide a session. "
                + "Go back to choose another preference.")
        }
    }

    /// The validated session for Start Shooting, resolved now (never a stale or deleted
    /// preference). Nil keeps the button disabled. Does not start the session.
    func makeConfiguration() -> PhotoSessionConfiguration? {
        if case .ready(let configuration) = status { return configuration }
        return nil
    }
}
