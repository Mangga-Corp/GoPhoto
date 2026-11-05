//
//  SessionSetupFlowView.swift
//  gophoto
//
//  Returning users configure sessions here: Preference Selection → Shot Size Selection
//  → START SHOOTING. Add New Preference opens Photo Session Setup, then the existing analysis
//  and Style Card flow returns to Preference Selection.
//
//  Session start: both paths call `PhotoSessionStore.startSession`, which resolves the request
//  again against the latest analysis, creates the session and only then records the last used
//  preference. `AppRootView` shows the camera whenever the store has a session, so a successful
//  start replaces this flow with the camera; a failure keeps the user here with the error.
//  The screens themselves never start a session.
//

import SwiftUI

enum SessionSetupRoute: Hashable {
    case shotSize(preferenceID: UUID)
    case photoSessionSetup
    case createdPreferenceAnalysis(preferenceID: UUID)
}

struct SessionSetupFlowView: View {
    @State private var selection: PreferenceSelectionViewModel
    @State private var path: [SessionSetupRoute] = []

    private let sessions: PhotoSessionStore
    private let handoffPreferenceID: UUID?
    private let hasPreferenceHandoff: Bool
    private let onHandoffConsumed: (() -> Void)?

    /// `initialPath`: screens already pushed when the flow opens (debug checks only; normally empty).
    init(preferences: PreferencesViewModel = .shared, sessions: PhotoSessionStore = .shared,
         initialPath: [SessionSetupRoute] = [], handoffPreferenceID: UUID? = nil,
         hasPreferenceHandoff: Bool = false, onHandoffConsumed: (() -> Void)? = nil) {
        _selection = State(initialValue: PreferenceSelectionViewModel(preferences: preferences, sessions: sessions))
        _path = State(initialValue: initialPath)
        self.sessions = sessions
        self.handoffPreferenceID = handoffPreferenceID
        self.hasPreferenceHandoff = hasPreferenceHandoff
        self.onHandoffConsumed = onHandoffConsumed
    }

    var body: some View {
        NavigationStack(path: $path) {
            PreferenceSelectionView(
                handoffPreferenceID: handoffPreferenceID,
                hasPreferenceHandoff: hasPreferenceHandoff,
                selection: selection,
                onContinue: { id in path.append(.shotSize(preferenceID: id)) },
                onAddNew: { path.append(.photoSessionSetup) },
                onHandoffConsumed: onHandoffConsumed
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SessionSetupRoute.self) { route in
                switch route {
                case .shotSize(let preferenceID):
                    ShotSizeSelectionDestination(preferenceID: preferenceID, preferences: selection.preferences,
                                                 sessions: sessions, onStartShooting: startSession)
                case .photoSessionSetup:
                    PhotoSessionSetupView(
                        onCreatePreference: { photos, name, completion in
                            selection.preferences.addPersisted(name: name, photos: photos) { result in
                                switch result {
                                case .success(let id):
                                    path = [.createdPreferenceAnalysis(preferenceID: id)]
                                    completion(.success(id))
                                case .failure(let error):
                                    completion(.failure(error))
                                }
                            }
                        },
                        onStartAnalyzing: { id in
                            path = [.createdPreferenceAnalysis(preferenceID: id)]
                        }
                    )
                    .toolbar(.hidden, for: .navigationBar)
                case .createdPreferenceAnalysis(let preferenceID):
                    OnboardingFlowView(
                        preferenceID: preferenceID,
                        startsAtStyleCard: false,
                        styleButtonTitle: "Continue",
                        onAnalysisCompleted: {},
                        onChooseOtherPhotos: {
                            selection.delete(preferenceID)
                            path = [.photoSessionSetup]
                        },
                        onFinish: {
                            selection.selectCreated(preferenceID)
                            path.removeAll()
                            return nil
                        }
                    )
                    .preferredColorScheme(.light)
                    .tint(GoPhotoDesign.purple)
                }
            }
        }
        // This flow only: the camera (another root) keeps its dark look.
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.sessionAccent)
    }

    /// START SHOOTING: the requested preference and shot size, resolved again by the store.
    private func startSession(_ configuration: PhotoSessionConfiguration) -> PhotoSessionError? {
        guard sessions.current == nil else { return nil }   // a session already started: ignore
        #if DEBUG
        DebugFixtures.beforeSessionStart(preferenceID: configuration.preferenceID)
        #endif
        switch sessions.startSession(preferenceID: configuration.preferenceID,
                                     shotSize: configuration.requestedShotSize) {
        case .success: return nil
        case .failure(let error): return error
        }
    }

}

/// Owns the Shot Size Selection state for one visit: a new view model per push (3/4 Body), gone
/// when the screen is popped. Nothing from a previous visit or session carries over.
private struct ShotSizeSelectionDestination: View {
    @State private var model: ShotSizeSelectionViewModel
    let onStartShooting: (PhotoSessionConfiguration) -> PhotoSessionError?

    init(preferenceID: UUID, preferences: PreferencesViewModel, sessions: PhotoSessionStore,
         onStartShooting: @escaping (PhotoSessionConfiguration) -> PhotoSessionError?) {
        _model = State(initialValue: ShotSizeSelectionViewModel(preferenceID: preferenceID,
                                                                preferences: preferences, sessions: sessions))
        self.onStartShooting = onStartShooting
    }

    var body: some View {
        ShotSizeSelectionView(model: model, onStartShooting: onStartShooting)
    }
}
