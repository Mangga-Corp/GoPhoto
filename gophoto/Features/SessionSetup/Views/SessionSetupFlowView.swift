//
//  SessionSetupFlowView.swift
//  gophoto
//
//  Returning users configure sessions here: Preference Selection → Camera. Add New Preference
//  opens Photo Session Setup, then the existing analysis and Style Card flow returns here; the
//  style card's Continue (or a saved custom preference) starts the session and opens the camera.
//
//  Session start: both paths call `PhotoSessionStore.startSession`, which resolves the request
//  again against the latest analysis, creates the session and only then records the last used
//  preference. `AppRootView` shows the camera whenever the store has a session, so a successful
//  start replaces this flow with the camera; a failure keeps the user here with the error.
//  The screens themselves never start a session.
//

import SwiftUI

enum SessionSetupRoute: Hashable {
    case photoSessionSetup
    case createdPreferenceAnalysis(preferenceID: UUID)
    /// Back on Photo Session Setup with a saved preference whose photos show too few people.
    case addMorePhotos(preferenceID: UUID)
}

struct SessionSetupFlowView: View {
    @State private var selection: PreferenceSelectionViewModel
    @State private var path: [SessionSetupRoute] = []

    private let sessions: PhotoSessionStore
    private let handoffPreferenceID: UUID?
    private let hasPreferenceHandoff: Bool
    private let onHandoffConsumed: (() -> Void)?

    init(preferences: PreferencesViewModel = .shared, sessions: PhotoSessionStore = .shared,
         handoffPreferenceID: UUID? = nil,
         hasPreferenceHandoff: Bool = false, onHandoffConsumed: (() -> Void)? = nil) {
        _selection = State(initialValue: PreferenceSelectionViewModel(preferences: preferences, sessions: sessions))
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
                onContinue: startSession,
                onAddNew: { path.append(.photoSessionSetup) },
                onHandoffConsumed: onHandoffConsumed
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SessionSetupRoute.self) { route in
                switch route {
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
                        },
                        onCustomPreferenceCreated: { id in
                            // Saved: straight to the camera. If the start fails, fall back to
                            // Preference Selection with the new preference selected.
                            selection.selectCreated(id)
                            if startSession(preferenceID: id) != nil { path.removeAll() }
                        },
                        showsBackButton: true
                    )
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
                        onNeedsMorePhotos: {
                            path = [.addMorePhotos(preferenceID: preferenceID)]
                        },
                        onFinish: {
                            selection.selectCreated(preferenceID)
                            if let error = startSession(preferenceID: preferenceID) {
                                return error.message
                            }
                            return nil
                        }
                    )
                    .preferredColorScheme(.light)
                    .tint(GoPhotoDesign.primary)
                case .addMorePhotos(let preferenceID):
                    // The same preference: added photos are saved to it, and Analyze runs it
                    // again (never a second preference).
                    PhotoSessionSetupView(
                        savedPreference: selection.preferences.preference(id: preferenceID),
                        onCreatePreference: { _, _, completion in
                            completion(.failure(PreferenceNameError(message: "This preference has already been saved.")))
                        },
                        onStartAnalyzing: { id in
                            path = [.createdPreferenceAnalysis(preferenceID: id)]
                        },
                        onCustomPreferenceCreated: { _ in },
                        // Cancel on the warning: this new preference is deleted and the user is
                        // back on Choose Preference (not Photo Session Setup).
                        onDiscardPreference: { id in
                            _ = selection.delete(id)
                            path.removeAll()
                        },
                        showsBackButton: true
                    )
                }
            }
        }
        // This flow only: the camera (another root) keeps its dark look.
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.primary)
    }

    /// Starts the selected preference with the existing default shot size; the store revalidates it.
    private func startSession(preferenceID: UUID) -> PhotoSessionError? {
        guard sessions.current == nil else { return nil }   // a session already started: ignore
        #if DEBUG
        DebugFixtures.beforeSessionStart(preferenceID: preferenceID)
        #endif
        switch sessions.startSession(preferenceID: preferenceID, shotSize: .initialSelection) {
        case .success: return nil
        case .failure(let error): return error
        }
    }
}
