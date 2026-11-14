import SwiftUI
import SwiftData

@main
struct MyApp: App {
    init() {
        AppFont.register()
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
                .font(AppFont.body)   // default for any text without its own font
        }
        .modelContainer(AppDatabase.container)
    }
}
