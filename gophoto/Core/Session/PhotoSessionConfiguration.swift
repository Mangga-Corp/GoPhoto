//
//  PhotoSessionConfiguration.swift
//  gophoto
//
//  One photography session: the preference and shot size the camera guides with.
//  Temporary: never saved. The saved preferences live in `PreferencesViewModel`; the last
//  preference used to start a session is the only session detail kept across launches.
//

import Foundation

/// The shot sizes a user can ask for when starting a session (Half Body, 3/4 Body, Full Body),
/// in screen order. Raw values match `PresetAnalysis.ShotSize`.
nonisolated enum SessionShotSize: String, CaseIterable, Hashable, Sendable {
    case half, threeQuarter, full

    /// Selected when a new session is being configured, and used for sessions that skip the
    /// shot size screen (first-time onboarding, a newly created preference). Not a saved default.
    static let initialSelection = SessionShotSize.threeQuarter

    /// The analysis shot size whose variant guides this request.
    var analysisShotSize: PresetAnalysis.ShotSize {
        switch self {
        case .half: .half
        case .threeQuarter: .threeQuarter
        case .full: .full
        }
    }

    /// Nil for `.quarter`, which a session cannot request.
    init?(analysisShotSize: PresetAnalysis.ShotSize) {
        switch analysisShotSize {
        case .half: self = .half
        case .threeQuarter: self = .threeQuarter
        case .full: self = .full
        case .quarter: return nil
        }
    }
}

/// Why a session could not be created.
nonisolated enum PhotoSessionError: Error, Equatable, Sendable {
    /// The preference does not exist (deleted, or never saved).
    case preferenceNotFound
    /// The preference has not been analysed yet.
    case analysisUnavailable
    /// The analysis ran but a required Vision request failed on every photo (see
    /// `AnalysisEvidenceSummary`), so its results can't guide a session.
    case analysisFailed
    /// The analysis has no shot variant at all (no photo's shot size could be read), so there is
    /// neither the requested variant nor a default to fall back to.
    case noShotVariant

    var message: String {
        switch self {
        case .preferenceNotFound: "This preference no longer exists."
        case .analysisUnavailable: "This preference hasn't been analyzed yet. Try again in a moment."
        case .analysisFailed: "We couldn't analyze this preference's photos. Edit its photos to try again."
        case .noShotVariant: "We couldn't read the framing of this preference's photos. Add photos that show a person and try again."
        }
    }
}

/// An immutable, validated session: created only through `resolve`, a new `id` every time.
nonisolated struct PhotoSessionConfiguration: Identifiable, Hashable, Sendable {
    let id: UUID
    let preferenceID: UUID
    /// What the user asked for. Never replaced by the fallback.
    let requestedShotSize: SessionShotSize
    /// The shot variant the camera guides with: the requested one when the preference has photos
    /// of it, else the preference's `defaultShot` (which may be `.quarter`).
    let effectiveShotSize: PresetAnalysis.ShotSize

    /// The camera guides with a different shot size than the one requested.
    var requiresShotSizeFallback: Bool { effectiveShotSize != requestedShotSize.analysisShotSize }

    private init(id: UUID, preferenceID: UUID, requestedShotSize: SessionShotSize,
                 effectiveShotSize: PresetAnalysis.ShotSize) {
        self.id = id
        self.preferenceID = preferenceID
        self.requestedShotSize = requestedShotSize
        self.effectiveShotSize = effectiveShotSize
    }

    /// Resolves the effective shot variant from the preference's analysis:
    /// 1. the requested shot size's variant, when the preference has photos of it;
    /// 2. otherwise the analysis default (`defaultShot`), flagged as a fallback;
    /// 3. otherwise the session cannot be created.
    /// No variant is invented and the analysis is not changed.
    static func resolve(preferenceID: UUID, analysis: PresetAnalysis?, requestedShotSize: SessionShotSize,
                        id: UUID = UUID()) -> Result<PhotoSessionConfiguration, PhotoSessionError> {
        guard let analysis else { return .failure(.analysisUnavailable) }
        if analysis.evidence?.requiredAnalysisFailed == true { return .failure(.analysisFailed) }
        let requested = requestedShotSize.analysisShotSize
        let effective: PresetAnalysis.ShotSize
        if analysis.shotVariant(requested) != nil {
            effective = requested
        } else if let fallback = analysis.defaultShot {
            effective = fallback
        } else {
            return .failure(.noShotVariant)
        }
        return .success(PhotoSessionConfiguration(id: id, preferenceID: preferenceID,
                                                  requestedShotSize: requestedShotSize,
                                                  effectiveShotSize: effective))
    }
}
