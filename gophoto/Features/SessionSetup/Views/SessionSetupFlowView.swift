//
//  SessionSetupFlowView.swift
//  gophoto
//
//  Returning users configure every new session here: Preference Selection → Shot Size Selection
//  → START SHOOTING. Add New Preference runs the existing picker → name → analysis → "Your style"
//  flow and its "Start shooting" goes straight to the camera.
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
}

struct SessionSetupFlowView: View {
    @State private var selection: PreferenceSelectionViewModel
    @State private var path: [SessionSetupRoute] = []
    @State private var isPresentingPicker = false
    /// Saved by the picker; its analysis flow opens once the picker has closed.
    @State private var savedPreferenceID: UUID?
    @State private var analyzingPreference: CreatedPreference?
    /// "Choose Other Photos" after an unusable analysis: the picker opens again once it closed.
    @State private var reopensPicker = false

    private struct CreatedPreference: Identifiable { let id: UUID }

    private let sessions: PhotoSessionStore
    private let handoffPreferenceID: UUID?

    /// `initialPath`: screens already pushed when the flow opens (debug checks only; normally empty).
    init(preferences: PreferencesViewModel = .shared, sessions: PhotoSessionStore = .shared,
         initialPath: [SessionSetupRoute] = [], handoffPreferenceID: UUID? = nil) {
        _selection = State(initialValue: PreferenceSelectionViewModel(preferences: preferences, sessions: sessions))
        _path = State(initialValue: initialPath)
        self.sessions = sessions
        self.handoffPreferenceID = handoffPreferenceID
    }

    var body: some View {
        NavigationStack(path: $path) {
            PreferenceSelectionView(
                handoffPreferenceID: handoffPreferenceID,
                selection: selection,
                onContinue: { id in path.append(.shotSize(preferenceID: id)) },
                onAddNew: { isPresentingPicker = true }
            )
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SessionSetupRoute.self) { route in
                switch route {
                case .shotSize(let preferenceID):
                    ShotSizeSelectionDestination(preferenceID: preferenceID, preferences: selection.preferences,
                                                 sessions: sessions, onStartShooting: startSession)
                }
            }
        }
        // This flow only: the camera (another root) keeps its dark look.
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.sessionAccent)
        // Existing picker → minimum photos → name prompt; saves with the existing `add`.
        .fullScreenCover(isPresented: $isPresentingPicker, onDismiss: openAnalysisIfSaved) {
            PhotoSessionPhotoPicker(
                onSave: { photos, name in
                    switch selection.preferences.add(name: name, photos: photos) {
                    case .success(let id):
                        savedPreferenceID = id
                        return nil
                    case .failure(let error):
                        return error.message
                    }
                },
                onFinish: { isPresentingPicker = false }
            )
            .ignoresSafeArea()
        }
        // Existing analysis (with retry) → "Your style" card ("Start shooting").
        .fullScreenCover(item: $analyzingPreference, onDismiss: reopenPickerIfRequested) { created in
            OnboardingFlowView(
                preferenceID: created.id,
                startsAtStyleCard: false,
                onAnalysisCompleted: {},
                onChooseOtherPhotos: { discardAndChooseAgain(created.id) },
                onFinish: { startCreatedSession(created.id) }
            )
            .preferredColorScheme(.light)
            .tint(GoPhotoDesign.purple)
        }
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

    /// The new preference's "Start shooting": its session at the initial 3/4 shot size.
    private func startCreatedSession(_ id: UUID) -> String? {
        guard sessions.current == nil else { return nil }
        switch sessions.startSession(preferenceID: id, shotSize: .initialSelection) {
        case .success:
            return nil
        case .failure(let error):
            selection.selectCreated(id)
            return error.message
        }
    }

    private func openAnalysisIfSaved() {
        guard let id = savedPreferenceID else { return }
        savedPreferenceID = nil
        analyzingPreference = CreatedPreference(id: id)
    }

    /// The new preference's photos showed no readable person: it is discarded (it was only
    /// just created here) and the picker opens again.
    private func discardAndChooseAgain(_ id: UUID) {
        selection.delete(id)
        reopensPicker = true
        analyzingPreference = nil
    }

    private func reopenPickerIfRequested() {
        guard reopensPicker else { return }
        reopensPicker = false
        isPresentingPicker = true
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
