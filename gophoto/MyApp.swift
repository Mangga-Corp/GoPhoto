import SwiftUI
import SwiftData

@main
struct MyApp: App {
    @State private var hasPreferences = PreferencesViewModel.shared.hasPreferences

    var body: some Scene {
        WindowGroup {
            Group {
                if hasPreferences {
                    CameraView()
                } else {
                    OnboardingFlowView(onFinish: { hasPreferences = true })
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hasPreferences)
        }
        .modelContainer(AppDatabase.container)
    }
}
