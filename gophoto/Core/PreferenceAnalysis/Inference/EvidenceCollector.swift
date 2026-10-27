import Foundation
import CoreGraphics

/// Stage B + C for one photo: runs every source concurrently and returns the
/// evidence bundle plus the heavy grids. Nothing here interprets the evidence.
nonisolated enum EvidenceCollector {

    /// - Parameter options: which angle-only evidence to collect (see `EvidenceOptions`).
    static func collect(from image: CGImage, models: AnalysisModels,
                        options: EvidenceOptions = .all) async -> (PhotoEvidence, PhotoArtifacts) {
        async let vision = VisionEvidenceRunner.run(on: image, includeBodyPose3D: options.bodyPose3D)
        async let model = ModelEvidenceRunner.run(on: image, models: models)
        async let lines = options.verticalLines ? VerticalLineExtractor.run(on: image) : skippedLines()

        let v = await vision
        let m = await model
        let (verticalLines, lineRecord) = await lines

        let evidence = PhotoEvidence(
            humans: v.humans, pose: v.pose, faces: v.faces, imageRoll: v.imageRoll,
            segmentation: m.segmentation, depth: m.depth, sceneContext: m.sceneContext,
            runs: v.records + m.records + [lineRecord],
            verticalLines: verticalLines,
            bodyPose3D: v.bodyPose3D)
        return (evidence, m.artifacts)
    }

    private static func skippedLines() -> (EvidenceOutcome<[ImageLineSegment]>, SourceRunRecord) {
        (.skipped("Not needed by this scan mode."),
         SourceRunRecord(source: .imageLineAnalysis, state: .skipped, durationMilliseconds: 0,
                         detail: "skipped (scan mode)"))
    }
}
