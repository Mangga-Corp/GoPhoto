import SwiftUI

struct AppRootView: View {
    @AppStorage("welcomeOnboardingCompleted") private var welcomeOnboardingCompleted = false
    @AppStorage("welcomeOnboardingStarted") private var welcomeOnboardingStarted = false
    @State private var isPresentingOnboardingFlow = false

    var body: some View {
        Group {
            if welcomeOnboardingCompleted || hasExistingPreferencesBeforeWelcome {
                CameraView()
                    .onAppear {
                        if hasExistingPreferencesBeforeWelcome {
                            welcomeOnboardingCompleted = true
                        }
                    }
            } else if isPresentingOnboardingFlow {
                OnboardingFlowView(
                    onFinish: {
                        welcomeOnboardingCompleted = true
                        welcomeOnboardingStarted = false
                        isPresentingOnboardingFlow = false
                    },
                    resumeExistingPreference: PreferencesViewModel.shared.hasPreferences
                )
            } else {
                WelcomeOnboardingView {
                    welcomeOnboardingStarted = true
                    isPresentingOnboardingFlow = true
                }
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isPresentingOnboardingFlow)
    }

    private var hasExistingPreferencesBeforeWelcome: Bool {
        PreferencesViewModel.shared.hasPreferences && !welcomeOnboardingStarted
    }
}
