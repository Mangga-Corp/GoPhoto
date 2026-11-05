//
//  AnalysisEvidenceSummary.swift
//  gophoto
//
//  What each evidence source did over a preset's photos, saved with `PresetAnalysis` so a failed
//  analysis stays distinguishable from one that ran and found nobody (before this, request
//  failures were only kept in memory and a failed run saved like "no person").
//
//  Required sources: without them no usable photography preference can exist.
//  - visionHumanRectangles: the only input to subject selection (`PhotoResultBuilder`); without it
//    framing, positioning and camera angle are all unknown.
//  - visionBodyPose: framing needs body landmarks (`SubjectFramingInterpreter`: full body only from
//    the ankles; the box-only fallback can claim half body at most) and the shot size cut uses the
//    neck / hip joints (`PreferenceAnalyzer.shotSize(of:)`).
//  Every other source (faces, horizon, 3D pose, segmentation, depth, scene classifier, edge lines)
//  is optional: the analysis has a fallback for each (e.g. the fixed-rule camera angle).
//

import Foundation

nonisolated struct AnalysisEvidenceSummary: Codable, Sendable, Equatable {
    /// What one source did for one photo (same cases as `SourceRunRecord.State`).
    enum Outcome: String, Codable, Sendable {
        /// Ran and returned results.
        case produced
        /// Ran successfully and found nothing (negative evidence, not a failure).
        case nothingDetected
        /// Could not run (e.g. no inference context): evidence is missing.
        case failed
        /// Not run on purpose.
        case skipped
    }

    struct Run: Sendable {
        let source: EvidenceSource
        let outcome: Outcome
        let detail: String
    }

    struct Counts: Codable, Sendable, Equatable {
        var produced = 0
        var nothingDetected = 0
        var failed = 0
        var skipped = 0
        var ranSuccessfully: Int { produced + nothingDetected }
    }

    static let requiredSources: [EvidenceSource] = [.visionHumanRectangles, .visionBodyPose]

    var photoCount: Int
    /// Per source (`EvidenceSource.rawValue`): how many photos ended in each outcome.
    var sources: [String: Counts]
    /// First failure message per source. Diagnostics only (logs, debug screens), never shown as is.
    var failureDetails: [String: String]

    /// - Parameter photoRuns: one entry per photo; nil = the photo could not be read at all
    ///   (counted as a failure of every required source).
    init(photoRuns: [[Run]?]) {
        photoCount = photoRuns.count
        var sources: [String: Counts] = [:]
        var details: [String: String] = [:]
        func add(_ source: EvidenceSource, _ outcome: Outcome, _ detail: String) {
            var counts = sources[source.rawValue] ?? Counts()
            switch outcome {
            case .produced: counts.produced += 1
            case .nothingDetected: counts.nothingDetected += 1
            case .failed: counts.failed += 1
            case .skipped: counts.skipped += 1
            }
            sources[source.rawValue] = counts
            if outcome == .failed, details[source.rawValue] == nil { details[source.rawValue] = detail }
        }
        for runs in photoRuns {
            guard let runs else {
                for source in Self.requiredSources { add(source, .failed, "photo could not be read") }
                continue
            }
            for run in runs { add(run.source, run.outcome, run.detail) }
            // A required source with no record for this photo did not run.
            for source in Self.requiredSources where !runs.contains(where: { $0.source == source }) {
                add(source, .failed, "not run")
            }
        }
        self.sources = sources
        failureDetails = details
    }

    /// Required sources that did not run successfully on any photo. Partial failures (some
    /// photos) are not listed: the photos where the source ran still count.
    var failedRequiredSources: [EvidenceSource] {
        guard photoCount > 0 else { return Self.requiredSources }
        return Self.requiredSources.filter { (sources[$0.rawValue]?.ranSuccessfully ?? 0) == 0 }
    }

    var requiredAnalysisFailed: Bool { !failedRequiredSources.isEmpty }

    /// One line for logs: which required source failed and why.
    var diagnosticDescription: String {
        failedRequiredSources.map { "\($0.rawValue): \(failureDetails[$0.rawValue] ?? "no successful run")" }
            .joined(separator: "; ")
    }
}

extension PresetAnalysis {
    /// Whether this analysis can be a photography preference.
    enum Usability: Equatable, Sendable {
        case usable
        /// A required request failed on every photo: the analysis did not really run.
        case requiredAnalysisFailed([EvidenceSource])
        /// The requests ran, but no photo gave a readable framing (e.g. no person found).
        case noUsableFraming
    }

    /// Analyses saved before `evidence` existed (nil) are judged on their data only: they are
    /// never assumed to have failed.
    var usability: Usability {
        if let failed = evidence?.failedRequiredSources, !failed.isEmpty { return .requiredAnalysisFailed(failed) }
        return defaultShot == nil && sittingVariant == nil ? .noUsableFraming : .usable
    }
}
