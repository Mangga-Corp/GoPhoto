import SwiftUI
import SwiftData

@main
struct MyApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    CameraView()
                } else {
                    OnboardingFlowView(onFinish: { hasCompletedOnboarding = true })
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hasCompletedOnboarding)
        }
        // Local Database for app, currently used for saving properties inside Core/Gallery/GalleryPhotos
        .modelContainer(AppDatabase.container)
    }
}
