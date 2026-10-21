import Foundation
import Combine

nonisolated enum PhotoRunState: Equatable, Sendable {
    case queued
    case running
    case finished(PhotoResultStatus)
}

/// One analysis run of a preset's photos, kept in memory so the results screen can show
/// every photo's details. Ported from `ai-model-kevin` without the benchmark tooling;
/// the camera angle always uses GeoCalib fp16.
@MainActor
final class AnalysisSession: ObservableObject {

    enum Phase: Equatable {
        case idle
        case running
        case completed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var photoStates: [UUID: PhotoRunState] = [:]
    @Published private(set) var results: [PhotoResult] = []
    @Published private(set) var profile: PreferenceProfile?
    @Published private(set) var photoOrder: [UUID] = []
    @Published private(set) var finishedAt: Date?

    let imageStore: PhotoImageStore
    let artifactStore: AnalysisArtifactStore

    private let engine: any PhotoAnalyzing
    private var selectionKey: [UUID] = []
    private var runTask: Task<Void, Never>?

    init(imageStore: PhotoImageStore = PhotoImageStore(),
         artifactStore: AnalysisArtifactStore = AnalysisArtifactStore(),
         engine: (any PhotoAnalyzing)? = nil) {
        self.imageStore = imageStore
        self.artifactStore = artifactStore
        self.engine = engine ?? AnalysisEngine(imageStore: imageStore, artifactStore: artifactStore)
    }

    // MARK: Progress

    var totalCount: Int { photoOrder.count }

    var finishedCount: Int {
        photoStates.values.filter { if case .finished = $0 { return true } else { return false } }.count
    }

    var progress: Double {
        totalCount == 0 ? 0 : Double(finishedCount) / Double(totalCount)
    }

    func result(for id: UUID) -> PhotoResult? { results.first { $0.id == id } }

    // MARK: Control

    /// Analyses a preset's photos and returns what the camera needs. Nil if cancelled.
    func analyze(_ photos: [PhotoItem]) async -> PresetAnalysis? {
        let references = photos.enumerated().map { index, item in
            ReferencePhoto(id: item.id, localIdentifier: "", image: item.image, selectionOrder: index)
        }
        start(photos: references)
        await runTask?.value
        guard phase == .completed, let profile else { return nil }
        return PreferenceAnalyzer.make(profile: profile, results: results, photoCount: photos.count)
    }

    /// Starts analysing `photos` unless this exact selection is already running or finished.
    func start(photos: [ReferencePhoto]) {
        let key = photos.map(\.id)
        if key == selectionKey, phase != .idle { return }

        runTask?.cancel()
        selectionKey = key
        photoOrder = key
        results = []
        profile = nil
        finishedAt = nil
        phase = .running
        photoStates = Dictionary(uniqueKeysWithValues: key.map { ($0, PhotoRunState.queued) })

        let sources = photos.map { PhotoSource($0) }
        let engine = self.engine
        let relay: @Sendable (PhotoRunEvent) -> Void = { [weak self] event in
            let session = self
            Task { @MainActor in session?.apply(event) }
        }

        // Runs never overlap: Core ML predictions cannot be interrupted, so a new run waits.
        let previous = runTask
        runTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            let finished = await engine.analyze(sources, events: relay)
            guard !Task.isCancelled, let self, self.selectionKey == key else { return }
            self.results = finished
            self.profile = ProfileAggregator.aggregate(finished)
            self.finishedAt = Date()
            self.phase = .completed
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
        selectionKey = []
        photoOrder = []
        photoStates = [:]
        results = []
        profile = nil
        phase = .idle
    }

    private func apply(_ event: PhotoRunEvent) {
        guard phase == .running else { return }
        switch event {
        case .started(let id): photoStates[id] = .running
        case .finished(let id, let status): photoStates[id] = .finished(status)
        }
    }
}
