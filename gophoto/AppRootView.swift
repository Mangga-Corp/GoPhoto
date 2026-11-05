import SwiftUI

private enum FirstTimeOnboardingStep: String {
    case photoSetup
    case preferenceSaved
    case analyzing
    case analysisComplete
    case styleCard
    case preferenceSelection
}

/// The app's routes, decided in this order:
/// 1. A photography session exists (`PhotoSessionStore.current`) → the camera, with that session.
/// 2. Onboarding completed → session setup (Preference Selection, or its empty state).
/// 3. A saved first-time preference awaiting analysis, or in analysis → the existing analysis flow.
/// 4. The existing style-card onboarding step → analysis/style flow.
/// 5. Other first-time onboarding states → Photo Session Setup.
/// 6. Saved preferences from a release without the completion flag → marked completed → 2.
/// 7. Otherwise → Welcome onboarding.
/// A session is only ever created by `PhotoSessionStore.startSession` (Start Shooting, a new
/// preference's style card, or the end of onboarding); app launch never creates one.
struct AppRootView: View {
    @AppStorage("welcomeOnboardingCompleted") private var welcomeOnboardingCompleted = false
    @AppStorage("welcomeOnboardingStarted") private var welcomeOnboardingStarted = false
    @AppStorage("firstTimeOnboardingStep")
    private var firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
    @AppStorage("firstTimeOnboardingPreferenceID")
    private var onboardingPreferenceIDString = ""
    @AppStorage(PreferencesViewModel.pendingOnboardingPreferenceIDKey)
    private var pendingOnboardingPreferenceIDString = ""

    var body: some View {
        Group {
            if let session = PhotoSessionStore.shared.current {
                // Only `current` is read on this path, so preference changes don't rebuild the camera.
                CameraView(sessionConfiguration: session, onClose: closeCamera)
                    .id(session.id)
                    #if DEBUG
                    .overlay(alignment: .bottom) { DebugSessionStatus() }
                    #endif
            } else if welcomeOnboardingCompleted {
                SessionSetupFlowView(
                    initialPath: debugInitialPath,
                    handoffPreferenceID: firstTimeOnboardingStep == FirstTimeOnboardingStep.preferenceSelection.rawValue
                        ? UUID(uuidString: onboardingPreferenceIDString) : nil,
                    hasPreferenceHandoff: firstTimeOnboardingStep == FirstTimeOnboardingStep.preferenceSelection.rawValue,
                    onHandoffConsumed: {
                        onboardingPreferenceIDString = ""
                        firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
                    }
                )
                    #if DEBUG
                    .overlay(alignment: .top) {
                        if DebugFixtures.storeName != nil { DebugFixtureStatus() }
                    }
                    #endif
            } else if welcomeOnboardingStarted,
                      ([FirstTimeOnboardingStep.preferenceSaved.rawValue,
                        FirstTimeOnboardingStep.analyzing.rawValue,
                        FirstTimeOnboardingStep.analysisComplete.rawValue,
                        FirstTimeOnboardingStep.styleCard.rawValue]
                        .contains(firstTimeOnboardingStep)),
                      let preference = savedOnboardingPreference {
                OnboardingFlowView(
                    preferenceID: preference.id,
                    startsAtStyleCard: shouldResumeStyleCard(for: preference),
                    styleButtonTitle: "Continue",
                    onAnalysisCompleted: {
                        pendingOnboardingPreferenceIDString = ""
                        firstTimeOnboardingStep = FirstTimeOnboardingStep.styleCard.rawValue
                    },
                    onChooseOtherPhotos: { chooseOtherOnboardingPhotos(preference.id) },
                    onFinish: continueToPreferenceSelection
                )
                .preferredColorScheme(.light)
                .tint(GoPhotoDesign.purple)
            } else if welcomeOnboardingStarted {
                NavigationStack {
                    PhotoSessionSetupView(
                        savedPreference: savedOnboardingPreference,
                        onCreatePreference: createOnboardingPreference,
                        onStartAnalyzing: { id in
                            guard savedOnboardingPreference?.id == id else { return }
                            firstTimeOnboardingStep = FirstTimeOnboardingStep.analyzing.rawValue
                        }
                    )
                }
                .preferredColorScheme(.light)
                .tint(GoPhotoDesign.purple)
            } else if !welcomeOnboardingStarted, PreferencesViewModel.shared.hasPreferences {
                // Older releases completed onboarding without setting the flag: returning users.
                SessionSetupFlowView()
                    .onAppear { welcomeOnboardingCompleted = true }
            } else {
                welcome
            }
        }
    }

    /// Welcome → Photo Session Setup.
    private var welcome: some View {
        WelcomeOnboardingView {
            firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
            onboardingPreferenceIDString = ""
            pendingOnboardingPreferenceIDString = ""
            welcomeOnboardingStarted = true
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.purple)
    }

    private func createOnboardingPreference(
        photos: [PhotoItem],
        name: String,
        completion: @escaping (Result<UUID, PreferenceNameError>) -> Void
    ) {
        let preferenceID = UUID()
        onboardingPreferenceIDString = preferenceID.uuidString
        pendingOnboardingPreferenceIDString = preferenceID.uuidString
        firstTimeOnboardingStep = FirstTimeOnboardingStep.preferenceSaved.rawValue
        PreferencesViewModel.shared.addPersisted(id: preferenceID, name: name, photos: photos) { result in
            switch result {
            case .success(let id):
                onboardingPreferenceIDString = id.uuidString
                firstTimeOnboardingStep = FirstTimeOnboardingStep.analyzing.rawValue
                completion(.success(id))
            case .failure(let error):
                onboardingPreferenceIDString = ""
                pendingOnboardingPreferenceIDString = ""
                firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
                completion(.failure(error))
            }
        }
    }

    private var debugInitialPath: [SessionSetupRoute] {
        #if DEBUG
        DebugFixtures.initialRoute
        #else
        []
        #endif
    }

    private var activePreference: Preference? {
        let preferences = PreferencesViewModel.shared
        return preferences.lastSelectedPreference ?? preferences.preferences.first
    }

    private var onboardingPreference: Preference? {
        return savedOnboardingPreference ?? activePreference
    }

    private var savedOnboardingPreference: Preference? {
        guard let id = UUID(uuidString: onboardingPreferenceIDString) else { return nil }
        return PreferencesViewModel.shared.preference(id: id)
    }

    private func shouldResumeStyleCard(for preference: Preference) -> Bool {
        guard let analysis = preference.analysis, analysis.isCurrent, analysis.usability == .usable else { return false }
        guard let _ = StyleSummary(analysis: analysis, photos: preference.photos) else { return false }
        return firstTimeOnboardingStep == FirstTimeOnboardingStep.styleCard.rawValue
            || firstTimeOnboardingStep == FirstTimeOnboardingStep.analyzing.rawValue
    }

    /// Continues to the existing Preference Selection screen without starting a session.
    private func continueToPreferenceSelection() -> String? {
        guard savedOnboardingPreference != nil else { return PhotoSessionError.preferenceNotFound.message }
        welcomeOnboardingCompleted = true
        welcomeOnboardingStarted = false
        firstTimeOnboardingStep = FirstTimeOnboardingStep.preferenceSelection.rawValue
        pendingOnboardingPreferenceIDString = ""
        return nil
    }

    /// No readable person in the onboarding photos: that preference is discarded (it is the one
    /// created a moment ago) and the picker opens again.
    private func chooseOtherOnboardingPhotos(_ id: UUID) {
        PreferencesViewModel.shared.delete(id: id, allowingLast: true)
        onboardingPreferenceIDString = ""
        pendingOnboardingPreferenceIDString = ""
        firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
    }

    /// Camera close: ends the session (once; the button disables itself) → session setup.
    private func closeCamera() {
        PhotoSessionStore.shared.endSession()
    }
}
