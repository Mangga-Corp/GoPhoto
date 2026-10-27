import SwiftUI

/// Debug screen: the full analysis of a preset (every photo and the combined profile),
/// the same screens as ai-model. Opened from the camera's debug panel.
struct AnalysisResultsScreen: View {
    let presetID: UUID?
    let presetName: String
    var preferences: PreferencesViewModel = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var session: AnalysisSession?

    var body: some View {
        NavigationStack {
            Group {
                if let session {
                    AnalysisSessionContent(session: session, onDone: { dismiss() })
                } else {
                    ContentUnavailableView {
                        Label("No details in memory", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Per-photo details are kept only until the app closes. Analyze this preset again to see them.")
                    } actions: {
                        Button("Analyze again") {
                            guard let presetID else { return }
                            preferences.reanalyze(id: presetID)
                            session = preferences.session(for: presetID)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(presetID == nil)
                    }
                }
            }
            .navigationTitle(presetName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            if let presetID { session = preferences.session(for: presetID) }
        }
    }
}

private struct AnalysisSessionContent: View {
    @ObservedObject var session: AnalysisSession
    let onDone: () -> Void

    var body: some View {
        Group {
            switch session.phase {
            case .idle, .running:
                AnalysisProgressPanel(session: session, onCancel: onDone)
            case .completed:
                ResultsOverviewView(session: session, onOpenCamera: onDone)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(for: PhotoDetailRoute.self) { route in
            PhotoResultDetailView(session: session, photoID: route.photoID)
        }
        .navigationDestination(for: ProfileRoute.self) { _ in
            ProfileDetailView(session: session)
        }
    }
}
