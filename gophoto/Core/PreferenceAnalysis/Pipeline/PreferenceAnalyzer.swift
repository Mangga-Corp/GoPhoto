import Foundation
import CoreGraphics
import UIKit

/// Turns a finished analysis (`PreferenceProfile` + per-photo results) into `PresetAnalysis`,
/// the targets the guided camera uses. The analysis itself runs in `AnalysisSession`:
/// Vision, DETR and Depth Anything read the subject and scene, GeoCalib fp16 the camera angle.
enum PreferenceAnalyzer {

    /// GeoCalib was trained on pitch within ±45°; results beyond that are not used as a target.
    nonisolated static let maxTargetPitch = 45.0

    // MARK: Profile -> camera targets

    nonisolated static func make(profile: PreferenceProfile, results: [PhotoResult],
                                 photoCount: Int, date: Date = Date()) -> PresetAnalysis {
        // Subject: median full-body box over photos with one valid main person.
        let boxes = results.compactMap { result -> CGRect? in
            let positioning = result.subjectPositioning
            guard positioning.assessment.isDetermined, positioning.isMeasurementValid else { return nil }
            return positioning.subjectBox
        }
        var subjectBox: CGRect?
        if !boxes.isEmpty {
            let cx = median(boxes.map { Double($0.midX) }), cy = median(boxes.map { Double($0.midY) })
            let w = median(boxes.map { Double($0.width) }), h = median(boxes.map { Double($0.height) })
            subjectBox = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        }
        let finding = profile.cameraAngle
        var counts: [String: Int] = [:]
        for (category, count) in finding.counts { counts[category.rawValue] = count }
        return PresetAnalysis(analyzedAt: date, photoCount: photoCount, subjectBox: subjectBox,
                              subjectPhotoCount: boxes.count,
                              angle: angleTarget(finding, results: results),
                              angleCounts: counts,
                              angleDeterminedCount: finding.validObservationCount,
                              angleLeadingShare: finding.dominantShare)
    }

    /// Majority rule (decided with the team): guide the angle only when one angle holds a
    /// majority; mixed angles mean the subject likes them all, so the camera stays quiet.
    nonisolated static func angleTarget(_ finding: CategoryFinding<CameraAngleCategory>,
                                        results: [PhotoResult]) -> PresetAnalysis.AngleTarget {
        switch finding.pattern {
        case .noEvidence:
            return .fixedRule
        case .singleObservation, .mixed:
            return .noGuidance
        case .recurring:
            guard let dominant = finding.dominant else { return .noGuidance }
            let ids = Set(finding.supportingPhotoIDs[dominant] ?? [])
            let pitches = results
                .filter { ids.contains($0.id) }
                .compactMap { $0.cameraAngle.pitchDownDegrees }
                .filter { abs($0) <= maxTargetPitch }
            guard !pitches.isEmpty else { return .noGuidance }
            return .match(category: dominant.rawValue, pitchDown: median(pitches))
        }
    }

    nonisolated static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        let mid = v.count / 2
        return v.count % 2 == 0 ? (v[mid - 1] + v[mid]) / 2 : v[mid]
    }
}
