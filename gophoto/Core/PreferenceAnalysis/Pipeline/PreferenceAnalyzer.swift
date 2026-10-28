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
        var analysis = build(profile: profile, results: results, photoCount: photoCount, date: date, only: nil)
        // One analysis per framing, from that framing's photos only (picked in the preset popover).
        var variants: [String: PresetAnalysis] = [:]
        for framing in [FramingCategory.fullBody, .halfBody] {
            let subset = results.filter { $0.subjectFraming.category == framing }
            guard !subset.isEmpty else { continue }
            variants[framing.rawValue] = build(profile: profile, results: subset, photoCount: subset.count,
                                               date: date, only: framing)
        }
        let cut = cutLevel(results)
        analysis.cutLevel = cut?.level
        analysis.cutLevelCount = cut?.count
        analysis.cutLevelOf = cut?.of
        for key in variants.keys {
            variants[key]?.cutLevel = analysis.cutLevel
            variants[key]?.cutLevelCount = analysis.cutLevelCount
            variants[key]?.cutLevelOf = analysis.cutLevelOf
        }
        analysis.framingVariants = variants.isEmpty ? nil : variants
        // One analysis per shot size (version 13): the popover offers the sizes with photos.
        var shots: [String: PresetAnalysis] = [:]
        let sizes = results.map { shotSize(of: $0) }
        for shot in PresetAnalysis.ShotSize.allCases {
            let subset = zip(results, sizes).filter { $0.1 == shot }.map { $0.0 }
            guard !subset.isEmpty else { continue }
            var variant = build(profile: profile, results: subset, photoCount: subset.count,
                                date: date, only: shot.framing)
            variant.shotSize = shot.rawValue
            variant.cutLevel = analysis.cutLevel
            variant.cutLevelCount = analysis.cutLevelCount
            variant.cutLevelOf = analysis.cutLevelOf
            shots[shot.rawValue] = variant
        }
        analysis.shotVariants = shots.isEmpty ? nil : shots
        analysis.photoFramings = Dictionary(results.map { ($0.id.uuidString, $0.subjectFraming.category.rawValue) },
                                            uniquingKeysWith: { first, _ in first })
        analysis.photoShotSizes = Dictionary(results.compactMap { result in
            shotSize(of: result).map { (result.id.uuidString, $0.rawValue) }
        }, uniquingKeysWith: { first, _ in first })
        return analysis
    }

    /// The analysis of `results`. `only`: these are the photos of one framing (a framing variant).
    nonisolated static func build(profile: PreferenceProfile, results: [PhotoResult], photoCount: Int,
                                  date: Date, only: FramingCategory?) -> PresetAnalysis {
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
        let framing = only ?? majority(profile.subjectFraming, excluding: [.other, .unknown])
        let side = eyeSide(results, framing: framing)
        let angle: PresetAnalysis.AngleTarget = side.map {
            PresetAnalysis.AngleTarget.match(category: $0.side.rawValue, pitchDown: $0.pitchDown)
        } ?? .fixedRule
        var analysis = PresetAnalysis(analyzedAt: date, photoCount: photoCount, subjectBox: subjectBox,
                              subjectPhotoCount: boxes.count,
                              angle: angle,
                              angleCounts: counts,
                              angleDeterminedCount: finding.validObservationCount,
                              angleLeadingShare: finding.dominantShare,
                              eyeElevation: side?.elevation,
                              headAngle: headAngle(results),
                              clippedTop: clipped(.top, results),
                              clippedBottom: clipped(.bottom, results),
                              framing: framing?.rawValue,
                              heightLevel: profile.viewpoint.flatMap {
                                  majority($0.heightLevel, excluding: [.unknown])?.rawValue
                              },
                              bodyAngle: bodyAngle(results),
                              eyeSide: side?.side.rawValue,
                              eyeSideSource: side?.source.rawValue,
                              eyeAboveShare: side?.aboveShare,
                              eyeSidePhotoCount: side?.photoCount)
        // Face height as a share of the frame height (not an angle): matches how big the person
        // looks, whatever lens the reference was shot with.
        let faces = results.compactMap { $0.cameraAngle.horizonCue?.headHeight }.filter { $0 > 0 }
        analysis.faceHeight = faces.isEmpty ? nil : median(faces)

        // Surroundings: how much the environment matters, and how busy the preferred backgrounds are.
        analysis.environmentProminence = profile.environment?.transferable.environmentProminence.dominant?.rawValue
        let objectShares = results.compactMap { result -> Double? in
            guard let seg = result.environment?.segmentation, seg.interpretation.isEligible,
                  seg.environmentFraction > 0 else { return nil }
            let objects = seg.environmentalRegions.filter { $0.family.kind == .object }
                .reduce(0) { $0 + $1.areaFraction }
            return min(1, objects / seg.environmentFraction)
        }
        analysis.preferredObjectShare = objectShares.isEmpty ? nil : median(objectShares)

        // Half body: the torso of each photo (neck, neck-to-hip length), for the crop.
        let torsos = results.compactMap { result -> (neck: CGPoint, length: Double)? in
            guard result.subjectFraming.category == .halfBody, let box = result.subjectPositioning.subjectBox,
                  let poses = result.evidence?.pose.value,
                  let pose = SubjectAssociation.pose(for: box, among: poses),
                  let neck = pose.reliable(.neck)?.point else { return nil }
            let hips = [pose.reliable(.leftHip), pose.reliable(.rightHip)].compactMap { $0?.point }
            guard let hip = pose.reliable(.root)?.point ?? (hips.isEmpty ? nil
                    : CGPoint(x: hips.map(\.x).reduce(0, +) / CGFloat(hips.count),
                              y: hips.map(\.y).reduce(0, +) / CGFloat(hips.count))) else { return nil }
            let length = Double(hip.y - neck.y)
            return length > 0.02 ? (neck, length) : nil
        }
        if !torsos.isEmpty {
            analysis.halfBodyNeck = CGPoint(x: median(torsos.map { Double($0.neck.x) }),
                                            y: median(torsos.map { Double($0.neck.y) }))
            let length = median(torsos.map { $0.length })
            analysis.halfBodyTorso = length
            // Bottom edge below the hips, in torso lengths: 1 - (neck + torso), over the torso.
            analysis.cutBelowHip = median(torsos.map { (1 - Double($0.neck.y) - $0.length) / $0.length })
        }
        return analysis
    }

    // MARK: Shot size (four levels, data only)

    /// Where the frame's bottom may cut, in torso lengths below the neck joint (neck → hip joint
    /// = 1): below it one-quarter (chest up), up to `halfMaxCut` half body (waist to just below the
    /// hips), deeper three-quarter (mid-thigh / knees up). Body proportions: chest ≈ 0.4,
    /// waist ≈ 0.7, hip joint 1, mid-thigh ≈ 1.45, knee ≈ 1.85.
    nonisolated static let quarterMaxCut = 0.55
    nonisolated static let halfMaxCut = 1.2
    /// Torso length (neck joint → hip joint) in face-box heights, when the hips are out of frame.
    nonisolated static let torsoInFaceHeights = 2.5

    /// The shot size of one photo, or nil when its framing was not read (or has no person).
    nonisolated static func shotSize(of result: PhotoResult) -> PresetAnalysis.ShotSize? {
        let framing = result.subjectFraming
        switch framing.category {
        case .fullBody:
            return .full
        case .other:
            // Head-only close-up: grouped with the tightest level.
            return framing.visibleExtent == .headOnly ? .quarter : nil
        case .halfBody:
            break
        default:
            return nil
        }
        if framing.visibleExtent == .toKnees { return .threeQuarter }

        // The frame's bottom (y = 1, top-left origin) below the neck, in torso lengths.
        if let box = result.subjectPositioning.subjectBox,
           let poses = result.evidence?.pose.value,
           let pose = SubjectAssociation.pose(for: box, among: poses),
           let neck = pose.reliable(.neck)?.point {
            let hips = [pose.reliable(.leftHip), pose.reliable(.rightHip)].compactMap { $0?.point }
            let hip = pose.reliable(.root)?.point ?? (hips.isEmpty ? nil
                : CGPoint(x: 0, y: hips.map(\.y).reduce(0, +) / CGFloat(hips.count)))
            var torso: Double?
            if let hip, hip.y - neck.y > 0.02 {
                torso = Double(hip.y - neck.y)
            } else if let face = result.cameraAngle.horizonCue?.headHeight, face > 0 {
                torso = face * torsoInFaceHeights
            }
            if let torso {
                let cut = (1 - Double(neck.y)) / torso
                if cut < quarterMaxCut { return .quarter }
                if cut < halfMaxCut { return .half }
                return .threeQuarter
            }
        }
        // No neck or torso: the deepest visible joints decide.
        switch framing.visibleExtent {
        case .headAndShoulders: return .quarter
        case .toHips: return .half
        default: return nil
        }
    }

    // MARK: Half-body cut level

    /// The body part where most half-body photos are cut, from the deepest reliable joint.
    nonisolated static func cutLevel(_ results: [PhotoResult]) -> (level: String, count: Int, of: Int)? {
        let levels = results.compactMap { result -> String? in
            guard result.subjectFraming.category == .halfBody else { return nil }
            switch result.subjectFraming.visibleExtent {
            case .headAndShoulders: return "chest"
            case .toHips: return "thigh"
            case .toKnees: return "shin"
            default: return nil
            }
        }
        guard !levels.isEmpty else { return nil }
        let counts = Dictionary(levels.map { ($0, 1) }, uniquingKeysWith: +)
        // Ties: the order chest < thigh < shin keeps the result stable.
        let order = ["chest", "thigh", "shin"]
        guard let best = counts.max(by: { a, b in
            a.value != b.value ? a.value < b.value : order.firstIndex(of: a.key)! > order.firstIndex(of: b.key)!
        }) else { return nil }
        return (best.key, best.value, levels.count)
    }

    // MARK: Eye side (above / below the subject's eyes)

    /// Photos needed before their side counts as the user's taste.
    nonisolated static let sideMinPhotos = 2
    /// Mean chance of "above" at or past which the photos agree (≥ 0.7 above, ≤ 0.3 below).
    nonisolated static let sideAgreement = 0.70

    nonisolated struct EyeVote: Sendable {
        /// Camera vs eyes, degrees (+ = camera above the eyes), and its standard deviation.
        let elevation: Double
        let sigma: Double
        /// Phone pitch (+ = down), when GeoCalib's pitch was certain enough.
        let pitchDown: Double?
        /// Chance the photo was taken from above the eyes: Φ(elevation / sigma). A photo near the
        /// eye line counts about half for each side instead of flipping on noise.
        let aboveChance: Double
    }

    nonisolated struct EyeSideResult: Sendable {
        let side: PresetAnalysis.EyeSide
        let source: PresetAnalysis.EyeSideSource
        let aboveShare: Double?
        let photoCount: Int
        /// Camera-vs-eyes target and phone pitch target, degrees.
        let elevation: Double
        let pitchDown: Double
    }

    /// The framing rule: full body is shot from eye level down, half body from eye level up.
    nonisolated static func ruleSide(for framing: FramingCategory?) -> PresetAnalysis.EyeSide? {
        switch framing {
        case .fullBody: PresetAnalysis.EyeSide.below
        case .halfBody: PresetAnalysis.EyeSide.above
        default: nil
        }
    }

    /// One vote per photo with a camera-vs-eyes angle, only photos with the preset's framing.
    nonisolated static func eyeVotes(_ results: [PhotoResult], framing: FramingCategory?) -> [EyeVote] {
        results.compactMap { result in
            if let framing, result.subjectFraming.category != framing { return nil }
            guard let detail = result.angleComparison?.details[.geoCalibLight],
                  let e = detail.cameraElevation, abs(e) <= maxTargetPitch,
                  let sigma = detail.cameraElevationUncertainty, sigma.isFinite, sigma > 0 else { return nil }
            let pitch = result.cameraAngle.pitchDownDegrees.flatMap { abs($0) <= maxTargetPitch ? $0 : nil }
            let chance = 0.5 * (1 + erf(e / (sigma * 2.0.squareRoot())))
            return EyeVote(elevation: e, sigma: sigma, pitchDown: pitch, aboveChance: chance)
        }
    }

    /// The user's taste first: the photos' side when they agree. The framing rule only decides
    /// when they split or too few were read. Nil without photos and without a framing.
    nonisolated static func eyeSide(_ results: [PhotoResult], framing: FramingCategory?) -> EyeSideResult? {
        let votes = eyeVotes(results, framing: framing)
        let rule = ruleSide(for: framing)
        let share = votes.isEmpty ? nil : votes.map(\.aboveChance).reduce(0, +) / Double(votes.count)

        func targets(_ used: [EyeVote], side: PresetAnalysis.EyeSide) -> (Double, Double) {
            var elevation = median(used.map(\.elevation))
            // Keep the target on the chosen side of the eye line (eye level is on both).
            elevation = side == .above ? max(elevation, 0) : min(elevation, 0)
            let pitches = used.compactMap(\.pitchDown)
            return (elevation, pitches.isEmpty ? 0 : median(pitches))
        }

        if votes.count >= sideMinPhotos, let share,
           share >= sideAgreement || share <= 1 - sideAgreement {
            let side: PresetAnalysis.EyeSide = share >= 0.5 ? .above : .below
            let agreeing = votes.filter { side == .above ? $0.aboveChance >= 0.5 : $0.aboveChance < 0.5 }
            let (elevation, pitch) = targets(agreeing, side: side)
            return EyeSideResult(side: side, source: .taste, aboveShare: share, photoCount: votes.count,
                                 elevation: elevation, pitchDown: pitch)
        }
        if !votes.isEmpty, let share, votes.count >= sideMinPhotos || rule == nil {
            let side = rule ?? (share >= 0.5 ? .above : .below)
            let (elevation, pitch) = targets(votes, side: side)
            return EyeSideResult(side: side, source: .mixed, aboveShare: share, photoCount: votes.count,
                                 elevation: elevation, pitchDown: pitch)
        }
        guard let rule else { return nil }
        return EyeSideResult(side: rule, source: .default, aboveShare: share, photoCount: votes.count,
                             elevation: 0, pitchDown: 0)
    }

    /// Face height as an angle: 2 * atan(h * tan(vFoV / 2)), h in image-height units.
    nonisolated static func headAngle(_ results: [PhotoResult]) -> Double? {
        let values = results.compactMap { result -> Double? in
            guard let head = result.cameraAngle.horizonCue?.headHeight,
                  let vfov = result.angleComparison?.details[.geoCalibLight]?.vfov,
                  head > 0, vfov > 0 else { return nil }
            return angle(ofHeight: head, verticalFOV: vfov)
        }
        return values.isEmpty ? nil : median(values)
    }

    /// Person box height as an angle, median over photos with a valid person and a field of view.
    nonisolated static func bodyAngle(_ results: [PhotoResult]) -> Double? {
        let values = results.compactMap { result -> Double? in
            let p = result.subjectPositioning
            guard p.assessment.isDetermined, p.isMeasurementValid, let box = p.subjectBox,
                  let vfov = result.angleComparison?.details[.geoCalibLight]?.vfov, vfov > 0 else { return nil }
            return angle(ofHeight: Double(box.height), verticalFOV: vfov)
        }
        return values.isEmpty ? nil : median(values)
    }

    /// Angular size of something `height` tall (image-height units) in a frame with `verticalFOV`.
    nonisolated static func angle(ofHeight height: Double, verticalFOV: Double) -> Double {
        2 * atan(height * tan(verticalFOV * .pi / 360)) * 180 / .pi
    }

    /// True when most photos with a measured person touch that edge.
    nonisolated static func clipped(_ edge: FrameEdge, _ results: [PhotoResult]) -> Bool? {
        let valid = results.map(\.subjectPositioning)
            .filter { $0.assessment.isDetermined && $0.isMeasurementValid }
        guard !valid.isEmpty else { return nil }
        let touching = valid.filter { $0.touchedEdges.contains(edge) }.count
        return Double(touching) / Double(valid.count) > 0.5
    }

    /// The dominant category when one holds a majority (`recurring`), else nil.
    nonisolated static func majority<C: Hashable & Sendable>(_ finding: CategoryFinding<C>,
                                                              excluding: Set<C>) -> C? {
        guard finding.pattern == .recurring, let dominant = finding.dominant,
              !excluding.contains(dominant) else { return nil }
        return dominant
    }

    nonisolated static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        let mid = v.count / 2
        return v.count % 2 == 0 ? (v[mid - 1] + v[mid]) / 2 : v[mid]
    }
}
