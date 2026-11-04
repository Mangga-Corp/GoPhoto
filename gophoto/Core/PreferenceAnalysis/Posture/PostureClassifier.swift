import Foundation
import CoreGraphics

/// Reads standing / sitting and the seated attributes of one reference photo from the body
/// pose Vision already produced, plus seat cues from the existing DETR segmentation.
/// A pure function: no models run here.
///
/// DECISION METHOD
/// 1. Thigh direction (hip → knee, against the vertical) decides standing or sitting when the
///    legs are in the frame: near vertical = standing, near horizontal = sitting. A thigh much
///    shorter than the torso is foreshortened (pointing at the camera) and is not used.
/// 2. Legs not usable (half body, or foreshortened): a seat next to the subject is the only
///    evidence of sitting, so it is read at low confidence; otherwise the posture is `unknown`.
/// 3. Support surface: a seat cue wins; else hips almost level with both ankles = floor;
///    else `unknown`. A chair is never assumed.
/// 4. Leg configuration: crossed when the ankles' x order differs from the hips' order, else
///    extended (both knees straight) or bent.
/// 5. Torso orientation: shoulder span over torso length.
///
/// The thresholds are starting values to tune on a device.
nonisolated enum PostureClassifier {

    // MARK: Tunables

    /// Thigh angle from vertical (degrees) at or below which a leg is standing.
    static let standingMaxThighAngle = 25.0
    /// Thigh angle from vertical (degrees) at or above which a leg is sitting.
    static let sittingMinThighAngle = 55.0
    /// Knee angle (degrees, 180 = straight) a standing leg must have.
    static let standingMinKneeAngle = 150.0
    /// A thigh shorter than this share of the torso is foreshortened and not judged.
    static let minThighToTorso = 0.25
    /// Hip-to-ankle drop, in torso lengths, at or below which the hips sit at ankle level.
    static let floorMaxAnkleDrop = 0.35
    /// Hip-to-ankle drop in torso lengths. A standing person, seen from the front, has ~1.7 or
    /// more; a person seated facing the camera (thighs pointing at the lens, so the thigh angle
    /// is useless) has ~1.0-1.2. At or below `sittingMaxAnkleDrop` the legs are folded.
    static let sittingMaxAnkleDrop = 1.25
    /// Same idea for a 3/4 shot that stops at the knees: knee-below-hip drop in torso lengths.
    /// Standing ~0.9 (a thigh is about a torso long); seated facing the camera ~0.4.
    static let sittingMaxKneeDrop = 0.6
    /// Confidence floor and ceiling of a sitting read made from the ankle drop alone.
    static let ankleDropConfidenceBase = 0.6
    static let ankleDropConfidenceSpan = 0.3
    /// Seat cue share (of the band around the subject) that counts as a seat.
    static let seatCueMinShare = 0.04
    /// With no legs in the frame a seat must fill more of the band to count. A chair or sofa
    /// (what people sit on) needs less than a bench, table, counter or bed, which people
    /// also stand beside.
    static let upperBodyChairCueMinShare = 0.05
    static let upperBodyCueMinShare = 0.10
    /// Confidence given to sitting read from a seat cue only (legs not visible).
    static let seatCueOnlyConfidence = 0.65
    /// Both knees at or above this angle = extended legs; any below `bentKneeMax` = bent.
    static let extendedKneeMin = 155.0
    static let bentKneeMax = 130.0
    /// Ankle x gap (frame-width units of the corrected space) needed to call an order.
    static let crossMargin = 0.02
    /// Shoulder span / torso length: at or above = front, at or above `threeQuarterMin` = 3/4.
    static let frontSpanMin = 0.62
    static let threeQuarterSpanMin = 0.30

    // MARK: Entry point

    /// - Parameters:
    ///   - pose: the main subject's pose (image space, top-left origin), or nil.
    ///   - hasSubject: a main person was found.
    ///   - aspect: image width / height, so angles are measured in pixels, not fractions.
    ///   - cues: seat evidence from `SupportCue.cues(from:)`.
    static func classify(pose: PoseCandidate?, hasSubject: Bool, aspect: Double,
                         cues: [SupportCue]) -> PostureReading {
        guard hasSubject else {
            return PostureReading(posture: attribute(.other, 0.7, .visible),
                                  torsoOrientation: attribute(.unknown, 0, .notVisible), sitting: nil)
        }
        guard let pose, let torso = torsoLength(pose, aspect: aspect) else { return .unreadable }

        let orientation = torsoOrientation(pose, aspect: aspect, torso: torso)
        let legs = [leg(pose, .leftHip, .leftKnee, .leftAnkle, aspect, torso),
                    leg(pose, .rightHip, .rightKnee, .rightAnkle, aspect, torso)].compactMap { $0 }
        let usable = legs.filter { $0.thighLength >= minThighToTorso * torso }
        let sitters = usable.filter { $0.thighAngle >= sittingMinThighAngle }
        let standers = usable.filter {
            $0.thighAngle <= standingMaxThighAngle && ($0.kneeAngle ?? 180) >= standingMinKneeAngle
        }

        if usable.isEmpty {
            if let reading = foldedLegsReading(legs: legs, pose: pose, aspect: aspect, cues: cues,
                                               orientation: orientation) { return reading }
            return upperBodyReading(cues: cues, orientation: orientation)
        }
        if !sitters.isEmpty && standers.isEmpty {
            let mean = average(sitters.map(\.confidence))
            let score = min(1, max(0, ((sitters.map(\.thighAngle).max() ?? 0) - 35) / 35))
            let visibility: AttributeVisibility = usable.allSatisfy(\.hasAnkle) ? .visible : .partiallyVisible
            return PostureReading(
                posture: attribute(.sitting, mean * (0.5 + 0.5 * score), visibility),
                torsoOrientation: orientation,
                sitting: SittingAttributes(supportSurface: supportSurface(legs: legs, cues: cues),
                                           legConfiguration: legConfiguration(legs: legs, pose: pose,
                                                                              aspect: aspect)))
        }
        if sitters.isEmpty && standers.count == usable.count {
            let mean = average(standers.map(\.confidence))
            let straightness = 1 - (standers.map(\.thighAngle).max() ?? 0) / standingMaxThighAngle
            let visibility: AttributeVisibility = usable.allSatisfy(\.hasAnkle) ? .visible : .partiallyVisible
            return PostureReading(posture: attribute(.standing, mean * (0.6 + 0.4 * straightness), visibility),
                                  torsoOrientation: orientation, sitting: nil)
        }
        // The thigh angle cannot tell (between the two, or the legs disagree): the ankle drop can.
        if let reading = foldedLegsReading(legs: legs, pose: pose, aspect: aspect, cues: cues,
                                           orientation: orientation) { return reading }
        // Visible, but still ambiguous: not guessed.
        return PostureReading(posture: attribute(.unknown, 0.3, .visible), torsoOrientation: orientation,
                              sitting: nil)
    }

    // MARK: Pieces

    /// Sitting read from how far the ankles are below the hips. Covers the front-facing seated
    /// person whose thighs point at the camera: their thigh angle is neither near vertical nor
    /// near horizontal, but the feet are close to the hips' height. Needs both ankles.
    private static func foldedLegsReading(legs: [Leg], pose: PoseCandidate, aspect: Double, cues: [SupportCue],
                                          orientation: ClassifiedAttribute<TorsoOrientation>) -> PostureReading? {
        let ankleDrops = legs.compactMap(\.ankleDrop)
        let kneeDrops = legs.map(\.kneeDrop)
        let limit: Double, mean: Double, span: Double
        if ankleDrops.count == 2 {
            limit = sittingMaxAnkleDrop; mean = ankleDrops.reduce(0, +) / 2; span = 0.5
            guard mean <= limit, (ankleDrops.max() ?? 0) <= limit * 1.15 else { return nil }
        } else if kneeDrops.count == 2 {
            // Ankles out of frame (3/4 shot): the knees say it.
            limit = sittingMaxKneeDrop; mean = kneeDrops.reduce(0, +) / 2; span = 0.3
            guard mean <= limit, (kneeDrops.max() ?? 0) <= limit * 1.15 else { return nil }
        } else { return nil }
        let margin = min(1, max(0, (limit - mean) / span))
        return PostureReading(
            posture: attribute(.sitting, ankleDropConfidenceBase + ankleDropConfidenceSpan * margin, .visible),
            torsoOrientation: orientation,
            sitting: SittingAttributes(supportSurface: supportSurface(legs: legs, cues: cues),
                                       legConfiguration: legConfiguration(legs: legs, pose: pose, aspect: aspect)))
    }

    private static func upperBodyReading(cues: [SupportCue],
                                         orientation: ClassifiedAttribute<TorsoOrientation>) -> PostureReading {
        let seat = cues.filter { $0.share >= ($0.surface == .chair ? upperBodyChairCueMinShare : upperBodyCueMinShare) }
            .max { $0.share < $1.share }
        guard let cue = seat else {
            return PostureReading(posture: attribute(.unknown, 0, .notVisible),
                                  torsoOrientation: orientation, sitting: nil)
        }
        return PostureReading(
            posture: attribute(.sitting, seatCueOnlyConfidence, .partiallyVisible),
            torsoOrientation: orientation,
            sitting: SittingAttributes(supportSurface: attribute(cue.surface, cueConfidence(cue), .partiallyVisible),
                                       legConfiguration: attribute(.unknown, 0, .notVisible)))
    }

    private static func supportSurface(legs: [Leg], cues: [SupportCue]) -> ClassifiedAttribute<SupportSurface> {
        let drops = legs.compactMap(\.ankleDrop)
        if let cue = bestCue(cues, minShare: seatCueMinShare) {
            return attribute(cue.surface, cueConfidence(cue), drops.isEmpty ? .partiallyVisible : .visible)
        }
        if let lowest = drops.max(), lowest <= floorMaxAnkleDrop {
            return attribute(.floor, 0.6 + 0.3 * (1 - max(0, lowest) / floorMaxAnkleDrop), .visible)
        }
        // A chair is never assumed from posture alone.
        return attribute(.unknown, 0.3, drops.isEmpty ? .notVisible : .visible)
    }

    private static func legConfiguration(legs: [Leg], pose: PoseCandidate,
                                         aspect: Double) -> ClassifiedAttribute<LegConfiguration> {
        let withAnkle = legs.filter(\.hasAnkle)
        guard !withAnkle.isEmpty else { return attribute(.unknown, 0, .notVisible) }
        let mean = average(withAnkle.map(\.confidence))
        let visibility: AttributeVisibility = withAnkle.count == 2 ? .visible : .partiallyVisible

        if let lh = pose.reliable(.leftHip), let rh = pose.reliable(.rightHip),
           let la = pose.reliable(.leftAnkle), let ra = pose.reliable(.rightAnkle) {
            let margin = crossMargin * aspect
            let hipGap = (Double(lh.point.x) - Double(rh.point.x)) * aspect
            let ankleGap = (Double(la.point.x) - Double(ra.point.x)) * aspect
            if abs(hipGap) > margin, abs(ankleGap) > margin, hipGap * ankleGap < 0 {
                return attribute(.crossed, mean * 0.8, visibility)
            }
        }
        let knees = withAnkle.compactMap(\.kneeAngle)
        if knees.allSatisfy({ $0 >= extendedKneeMin }) { return attribute(.extended, mean * 0.85, visibility) }
        if knees.contains(where: { $0 < bentKneeMax }) { return attribute(.bent, mean * 0.85, visibility) }
        return attribute(.unknown, 0.3, visibility)
    }

    private static func torsoOrientation(_ pose: PoseCandidate, aspect: Double,
                                         torso: Double) -> ClassifiedAttribute<TorsoOrientation> {
        guard let l = pose.reliable(.leftShoulder), let r = pose.reliable(.rightShoulder) else {
            return attribute(.unknown, 0, .notVisible)
        }
        let span = hypot((Double(l.point.x) - Double(r.point.x)) * aspect, Double(l.point.y) - Double(r.point.y))
        let ratio = span / torso
        let value: TorsoOrientation = ratio >= frontSpanMin ? .frontFacing
            : ratio >= threeQuarterSpanMin ? .threeQuarterFacing : .sideFacing
        // The closer the ratio is to a boundary, the less sure the call.
        let margin = min(abs(ratio - frontSpanMin), abs(ratio - threeQuarterSpanMin))
        let confidence = average([l.confidence, r.confidence]) * (0.5 + 0.5 * min(1, margin / 0.15))
        return attribute(value, confidence, .visible)
    }

    // MARK: Geometry

    private struct Leg {
        let thighAngle: Double      // degrees from vertical, 0 = straight down
        let thighLength: Double     // pixel-space units (image height = 1)
        let kneeAngle: Double?      // 180 = straight
        let kneeDrop: Double        // knee below hip, in torso lengths
        let ankleDrop: Double?      // ankle below hip, in torso lengths
        let confidence: Double
        var hasAnkle: Bool { kneeAngle != nil }
    }

    private static func leg(_ pose: PoseCandidate, _ hipJoint: BodyJoint, _ kneeJoint: BodyJoint,
                            _ ankleJoint: BodyJoint, _ aspect: Double, _ torso: Double) -> Leg? {
        guard let hip = pose.reliable(hipJoint), let knee = pose.reliable(kneeJoint) else { return nil }
        func point(_ l: BodyLandmark) -> CGPoint { CGPoint(x: l.point.x * aspect, y: l.point.y) }
        let h = point(hip), k = point(knee)
        let thigh = CGPoint(x: k.x - h.x, y: k.y - h.y)
        var kneeAngle: Double?, drop: Double?
        var confidences = [hip.confidence, knee.confidence]
        if let ankle = pose.reliable(ankleJoint) {
            let a = point(ankle)
            let u = CGPoint(x: h.x - k.x, y: h.y - k.y), v = CGPoint(x: a.x - k.x, y: a.y - k.y)
            let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
            if lengths > 0 {
                kneeAngle = acos(min(1, max(-1, Double((u.x * v.x + u.y * v.y) / lengths)))) * 180 / .pi
            }
            drop = Double(a.y - h.y) / torso
            confidences.append(ankle.confidence)
        }
        return Leg(thighAngle: atan2(abs(Double(thigh.x)), Double(thigh.y)) * 180 / .pi,
                   thighLength: Double(hypot(thigh.x, thigh.y)), kneeAngle: kneeAngle, kneeDrop: Double(k.y - h.y) / torso, ankleDrop: drop,
                   confidence: average(confidences))
    }

    /// Neck to hip length in pixel-space units, nil without a neck or a hip.
    private static func torsoLength(_ pose: PoseCandidate, aspect: Double) -> Double? {
        guard let neck = pose.reliable(.neck) else { return nil }
        let hips = [pose.reliable(.root), pose.reliable(.leftHip), pose.reliable(.rightHip)].compactMap { $0 }
        guard !hips.isEmpty else { return nil }
        let hx = hips.map { Double($0.point.x) }.reduce(0, +) / Double(hips.count)
        let hy = hips.map { Double($0.point.y) }.reduce(0, +) / Double(hips.count)
        let length = hypot((hx - Double(neck.point.x)) * aspect, hy - Double(neck.point.y))
        return length > 0.02 ? length : nil
    }

    // MARK: Helpers

    private static func bestCue(_ cues: [SupportCue], minShare: Double) -> SupportCue? {
        cues.filter { $0.share >= minShare }.max { $0.share < $1.share }
    }

    private static func cueConfidence(_ cue: SupportCue) -> Double { min(1, 0.6 + 0.3 * min(1, cue.share / 0.15)) }

    private static func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func attribute<V: Codable & Equatable & Sendable>(
        _ value: V, _ confidence: Double, _ visibility: AttributeVisibility) -> ClassifiedAttribute<V> {
        ClassifiedAttribute(value: value, confidence: min(1, max(0, confidence)), visibility: visibility)
    }
}
