import SwiftUI

@main
struct MyApp: App {
    @State private var showCamera = false

    var body: some Scene {
        WindowGroup {
            ChoosePhotosFlowView(onCameraTapped: {
                showCamera = true
            })
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $showCamera) {
                CameraView()
            }
        }
    }
}
