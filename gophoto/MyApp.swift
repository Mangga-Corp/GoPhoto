import SwiftUI
import SwiftData

@main
struct MyApp: App {

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Local Database for app, currently used for saving properties inside Core/Gallery/GalleryPhotos
        .modelContainer(AppDatabase.container)
    }
}
