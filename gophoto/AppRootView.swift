import SwiftUI

private enum FirstTimeOnboardingStep: String {
    case photoSetup
    case preferenceSaved
    case analyzing
    case styleCard
}

/// The app's routes, decided in this order:
/// 1. A photography session exists (`PhotoSessionStore.current`) → the camera, with that session.
/// 2. Onboarding completed → session setup (Preference Selection, or its empty state).
/// 3. First-time onboarding explicitly in its analysis step → analysis → "Your style" card.
/// 4. Other first-time onboarding states, including the saved Phase 2 preference → Photo Session Setup.
/// 5. Saved preferences from a release without the completion flag → marked completed → 2.
/// 6. Otherwise → Welcome onboarding.
/// A session is only ever created by `PhotoSessionStore.startSession` (Start Shooting, a new
/// preference's style card, or the end of onboarding); app launch never creates one.
struct AppRootView: View {
    @AppStorage("welcomeOnboardingCompleted") private var welcomeOnboardingCompleted = false
    @AppStorage("welcomeOnboardingStarted") private var welcomeOnboardingStarted = false
    @AppStorage("firstTimeOnboardingStep")
    private var firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
    @AppStorage(PreferencesViewModel.pendingOnboardingPreferenceIDKey)
    private var onboardingPreferenceIDString = ""

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
                SessionSetupFlowView(initialPath: debugInitialPath)
                    #if DEBUG
                    .overlay(alignment: .top) {
                        if DebugFixtures.storeName != nil { DebugFixtureStatus() }
                    }
                    #endif
            } else if welcomeOnboardingStarted,
                      firstTimeOnboardingStep != FirstTimeOnboardingStep.analyzing.rawValue,
                      firstTimeOnboardingStep != FirstTimeOnboardingStep.styleCard.rawValue {
                PhotoSessionSetupView(
                    savedPreference: savedOnboardingPreference,
                    onCreatePreference: createOnboardingPreference
                )
                .preferredColorScheme(.light)
                .tint(GoPhotoDesign.purple)
            } else if welcomeOnboardingStarted, let preference = onboardingPreference {
                OnboardingFlowView(
                    preferenceID: preference.id,
                    startsAtStyleCard: shouldResumeStyleCard(for: preference),
                    onAnalysisCompleted: {
                        firstTimeOnboardingStep = FirstTimeOnboardingStep.styleCard.rawValue
                    },
                    onChooseOtherPhotos: { chooseOtherOnboardingPhotos(preference.id) },
                    onFinish: completeOnboarding
                )
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
            welcomeOnboardingStarted = true
        }
        .preferredColorScheme(.light)
        .tint(GoPhotoDesign.purple)
    }

    private func createOnboardingPreference(
        photos: [PhotoItem],
        name: String,
        completion: @escaping (String?) -> Void
    ) {
        let preferenceID = UUID()
        onboardingPreferenceIDString = preferenceID.uuidString
        PreferencesViewModel.shared.addPersisted(id: preferenceID, name: name, photos: photos) { result in
            switch result {
            case .success(let id):
                onboardingPreferenceIDString = id.uuidString
                firstTimeOnboardingStep = FirstTimeOnboardingStep.preferenceSaved.rawValue
                completion(nil)
            case .failure(let error):
                onboardingPreferenceIDString = ""
                completion(error.message)
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

    /// The style card's "Start shooting" at the end of onboarding: the new preference's session at
    /// the initial 3/4 shot size. Onboarding is completed only once that session exists; on
    /// failure the card stays with the error.
    private func completeOnboarding() -> String? {
        guard let preference = onboardingPreference else { return PhotoSessionError.preferenceNotFound.message }
        if case .failure(let error) = PhotoSessionStore.shared.startSession(preferenceID: preference.id,
                                                                            shotSize: .initialSelection) {
            return error.message
        }
        welcomeOnboardingCompleted = true
        welcomeOnboardingStarted = false
        firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
        onboardingPreferenceIDString = ""
        return nil
    }

    /// No readable person in the onboarding photos: that preference is discarded (it is the one
    /// created a moment ago) and the picker opens again.
    private func chooseOtherOnboardingPhotos(_ id: UUID) {
        PreferencesViewModel.shared.delete(id: id, allowingLast: true)
        onboardingPreferenceIDString = ""
        firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
    }

    /// Camera close: ends the session (once; the button disables itself) → session setup.
    private func closeCamera() {
        PhotoSessionStore.shared.endSession()
    }
}
