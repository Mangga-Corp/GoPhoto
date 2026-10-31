import SwiftUI

private enum FirstTimeOnboardingStep: String {
    case photoSetup
    case analyzing
    case styleCard
}

struct AppRootView: View {
    @AppStorage("welcomeOnboardingCompleted") private var welcomeOnboardingCompleted = false
    @AppStorage("welcomeOnboardingStarted") private var welcomeOnboardingStarted = false
    @AppStorage("firstTimeOnboardingStep")
    private var firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
    @State private var onboardingPreferenceID: UUID?

    var body: some View {
        Group {
            if welcomeOnboardingCompleted {
                CameraView()
            } else if welcomeOnboardingStarted {
                if let preference = onboardingPreference {
                    OnboardingFlowView(
                        preferenceID: preference.id,
                        startsAtStyleCard: shouldResumeStyleCard(for: preference),
                        onAnalysisCompleted: {
                            firstTimeOnboardingStep = FirstTimeOnboardingStep.styleCard.rawValue
                        },
                        onFinish: completeOnboarding
                    )
                } else {
                    PhotoSessionSetupView { preferenceID in
                        onboardingPreferenceID = preferenceID
                        firstTimeOnboardingStep = FirstTimeOnboardingStep.analyzing.rawValue
                    }
                }
            } else if PreferencesViewModel.shared.hasPreferences {
                CameraView()
                    .onAppear {
                        // Older releases completed onboarding by routing saved-preference users
                        // directly to the camera without setting the completion flag.
                        welcomeOnboardingCompleted = true
                    }
            } else {
                WelcomeOnboardingView {
                    firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
                    welcomeOnboardingStarted = true
                }
            }
        }
    }

    private var activePreference: Preference? {
        let preferences = PreferencesViewModel.shared
        return preferences.selectedPreference ?? preferences.preferences.first
    }

    private var onboardingPreference: Preference? {
        let preferences = PreferencesViewModel.shared
        return onboardingPreferenceID.flatMap(preferences.preference(id:)) ?? activePreference
    }

    private func shouldResumeStyleCard(for preference: Preference) -> Bool {
        guard preference.analysis?.isCurrent == true else { return false }
        guard let _ = StyleSummary(analysis: preference.analysis, photos: preference.photos) else { return false }
        return firstTimeOnboardingStep == FirstTimeOnboardingStep.styleCard.rawValue
            || firstTimeOnboardingStep == FirstTimeOnboardingStep.analyzing.rawValue
    }

    private func completeOnboarding() {
        welcomeOnboardingCompleted = true
        welcomeOnboardingStarted = false
        firstTimeOnboardingStep = FirstTimeOnboardingStep.photoSetup.rawValue
    }
}
