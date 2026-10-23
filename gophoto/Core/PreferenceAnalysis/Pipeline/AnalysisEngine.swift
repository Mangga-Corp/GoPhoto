import Foundation
import CoreGraphics
import UIKit

/// Progress signal for one photo. Emitted only when real work starts or ends.
nonisolated enum PhotoRunEvent: Sendable {
    case started(UUID)
    case finished(UUID, PhotoResultStatus)
}

/// Anything that turns selected photos into results. The session depends on
/// this seam so tests and previews can supply fixed results.
nonisolated protocol PhotoAnalyzing: Sendable {
    func analyze(_ sources: [PhotoSource],
                 events: @escaping @Sendable (PhotoRunEvent) -> Void) async -> [PhotoResult]
}

/// Orchestrates Stages A through E for a set of photos.
///
/// - Photos are processed two at a time (the Core ML models are single actors,
///   so more parallelism only adds memory pressure).
/// - Each photo's result is cached by its stable ID, camera-angle scan mode and scan
///   token. Asking again for the same photo in the same scan returns the cached result
///   and runs NO inference; a different mode or `AnalysisSession.rescan()` runs again.
/// - The Core ML models live only for the duration of a run; they are released
///   afterwards so the camera screen starts with that memory free.
/// - Every photo records where its time went (`PhotoScanTiming`) for benchmarking.
actor AnalysisEngine: PhotoAnalyzing {

    static let maximumConcurrentPhotos = 2

    private let imageStore: PhotoImageStore
    private let artifactStore: AnalysisArtifactStore
    private var cache: [String: PhotoResult] = [:]

    init(imageStore: PhotoImageStore, artifactStore: AnalysisArtifactStore) {
        self.imageStore = imageStore
        self.artifactStore = artifactStore
    }

    private static func cacheKey(_ source: PhotoSource) -> String {
        "\(source.id.uuidString)|\(source.angleMode.rawValue)|\(source.scanToken)"
    }

    /// Analyses `sources` and returns results in selection order.
    /// Returns early with whatever finished if the calling task is cancelled.
    func analyze(_ sources: [PhotoSource],
                 events: @escaping @Sendable (PhotoRunEvent) -> Void) async -> [PhotoResult] {

        let pending = sources.filter { cache[Self.cacheKey($0)] == nil }
        if !pending.isEmpty {
            let models = AnalysisModels()
            // Only the GeoCalib network the chosen scan mode needs (none in Original mode).
            let geoCalibModes = Set(pending.compactMap { $0.angleMode.geoCalibMode })
            let geoCalib: GeoCalibModels? = geoCalibModes.isEmpty ? nil : GeoCalibModels(modes: Array(geoCalibModes))
            let images = imageStore, artifacts = artifactStore

            await withTaskGroup(of: (String, PhotoResult).self) { group in
                var iterator = pending.makeIterator()

                func addNext() {
                    guard !Task.isCancelled, let source = iterator.next() else { return }
                    group.addTask {
                        let result = await Self.process(source, models: models, geoCalib: geoCalib, images: images,
                                                        artifacts: artifacts, events: events)
                        return (Self.cacheKey(source), result)
                    }
                }

                for _ in 0..<Self.maximumConcurrentPhotos { addNext() }
                while let finished = await group.next() {
                    cache[finished.0] = finished.1
                    addNext()
                }
            }
        }

        return sources.compactMap { cache[Self.cacheKey($0)] }.sorted { $0.selectionOrder < $1.selectionOrder }
    }

    /// The most recent cached result for a photo, in any scan mode.
    func cachedResult(for id: UUID) -> PhotoResult? { cache.values.first { $0.id == id } }

    func reset() {
        cache.removeAll()
    }

    // MARK: One photo

    private static func process(_ source: PhotoSource,
                                models: AnalysisModels,
                                geoCalib: GeoCalibModels?,
                                images: PhotoImageStore,
                                artifacts: AnalysisArtifactStore,
                                events: @Sendable (PhotoRunEvent) -> Void) async -> PhotoResult {
        events(.started(source.id))
        func ms(_ a: Date, _ b: Date) -> Double { b.timeIntervalSince(a) * 1000 }
        let tStart = Date()

        // Stage A
        let prepared = PhotoPreparer.prepare(source)
        let tPrepared = Date()
        let result: PhotoResult
        switch prepared.outcome {
        case .unreadable(let reason):
            result = PhotoResultBuilder.unreadable(prepared, reason: reason)

        case .ready(let image, let record):
            images.set(UIImage(cgImage: image, scale: 1, orientation: .up), for: prepared.id)

            // Stages B + C. GeoCalib modes skip evidence only the original angle method uses.
            let options = EvidenceOptions(angleMode: source.angleMode)
            let (evidence, grids) = await EvidenceCollector.collect(from: image, models: models, options: options)
            artifacts.set(grids, for: prepared.id)
            let tEvidence = Date()

            // Stages D + E
            let built = PhotoResultBuilder.build(prepared: prepared, record: record,
                                                 evidence: evidence, artifacts: grids)
            let tBuilt = Date()

            // Camera angle with the chosen scan mode only.
            let scan = GeoCalibAngleInterpreter.scan(source.angleMode, original: built.cameraAngle, image: image,
                                                     evidence: evidence, models: geoCalib,
                                                     focalLength35mm: record.focalLength35mm)
            let tAngle = Date()

            var scanned = built.withAngleScan(scan, method: source.angleMode)
            let detail = scan.details[source.angleMode]
            scanned.scanTiming = PhotoScanTiming(
                prepareMs: ms(tStart, tPrepared), evidenceMs: ms(tPrepared, tEvidence),
                interpretMs: ms(tEvidence, tBuilt), angleModelMs: ms(tBuilt, tAngle),
                geoCalibPreprocessMs: detail?.preprocessMs, geoCalibPredictMs: detail?.predictMs,
                geoCalibOptimizeMs: detail?.optimizeMs)
            scanned.modelLoadMs = geoCalib?.loadMs
            result = scanned
        }

        events(.finished(source.id, result.status))
        return result
    }
}
