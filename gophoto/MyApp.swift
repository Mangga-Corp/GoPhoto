import SwiftUI
import SwiftData

@main
struct MyApp: App {
    init() {
        #if DEBUG
        DebugFixtures.prepareLaunchState()
        DebugFixtures.seedIfNeeded()
        DebugFixtures.diagnoseVisionIfRequested()
        DebugFixtures.scheduleDeletionIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(AppDatabase.container)
    }
}
