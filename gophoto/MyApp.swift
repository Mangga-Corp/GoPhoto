import SwiftUI
import SwiftData

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(AppDatabase.container)
    }
}
