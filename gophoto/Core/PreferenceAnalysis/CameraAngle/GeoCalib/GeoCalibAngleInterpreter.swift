import CoreGraphics
import Foundation

// MARK: - Camera-angle scan modes
//
// The user picks ONE mode before scanning (photo selection screen), so each scan's time can be
// benchmarked on its own:
//
//   original       Kevin/Brandon's evidence fusion (horizon, background verticals, 3D pose).
//   geoCalibHeavy  GeoCalib fp32: camera pitch / roll / focal from the image itself.
//   geoCalibLight  GeoCalib fp16: same, smaller network.
//
// In the GeoCalib modes the evidence that only the original method needs (3D body pose,
// background vertical lines) is not collected, so the time difference between modes is the
// angle method alone. Shared steps (Vision people/pose/face, DETR, depth) always run.
//
// GeoCalib reads the camera's pitch, roll and lens from the whole image. Combined with the
// subject's eye point it gives the camera's elevation relative to the eyes, the same quantity
// the original fusion estimates, so both feed the same `CameraAngleResult`.

nonisolated enum CameraAngleMethod: String, CaseIterable, Identifiable, Sendable, Hashable {
    case original
    case geoCalibHeavy
    case geoCalibLight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .geoCalibHeavy: return "GeoCalib Heavy"
        case .geoCalibLight: return "GeoCalib Light"
        }
    }

    var shortTitle: String {
        switch self {
        case .original: return "Original"
        case .geoCalibHeavy: return "Heavy"
        case .geoCalibLight: return "Light"
        }
    }

    var caption: String {
        switch self {
        case .original: return "Horizon, background lines and 3D pose"
        case .geoCalibHeavy: return "GeoCalib fp32 (114 MB)"
        case .geoCalibLight: return "GeoCalib fp16 (57 MB)"
        }
    }

    var geoCalibMode: GeoCalibMode? {
        switch self {
        case .original: return nil
        case .geoCalibHeavy: return .heavy
        case .geoCalibLight: return .light
        }
    }
}

/// Raw numbers behind one method's result, for the comparison screen.
nonisolated struct CameraAngleMethodDetail: Sendable, Equatable {
    /// Camera height relative to the eyes, degrees, positive = camera above the eyes.
    var cameraElevation: Double?
    /// ± one standard deviation (GeoCalib only).
    var cameraElevationUncertainty: Double?
    /// Camera pitch, degrees, positive = tilted DOWN (same convention as `CameraAngleResult`).
    var pitchDown: Double?
    var pitchUncertainty: Double?
    var roll: Double?
    var rollUncertainty: Double?
    var focalPx: Double?
    var vfov: Double?
    /// Time spent on this method for this photo, ms (GeoCalib only; preprocessing is shared).
    var preprocessMs: Double?
    var predictMs: Double?
    var optimizeMs: Double?
    /// Why the method produced nothing, when it failed.
    var error: String?

    var totalMs: Double? {
        guard let p = predictMs, let o = optimizeMs else { return nil }
        return (preprocessMs ?? 0) + p + o
    }
}

/// The camera-angle result(s) of a scan for one photo, with the numbers behind them.
nonisolated struct CameraAngleComparison: Sendable, Equatable {
    var results: [CameraAngleMethod: CameraAngleResult]
    var details: [CameraAngleMethod: CameraAngleMethodDetail]
}

extension PhotoResult {
    /// The same photo result with its camera angle taken from `method`.
    nonisolated func usingCameraAngle(_ method: CameraAngleMethod) -> PhotoResult {
        guard method != .original, let angle = angleComparison?.results[method] else { return self }
        return PhotoResult(
            id: id, selectionOrder: selectionOrder, localIdentifier: localIdentifier, preparation: preparation,
            status: status, evidence: evidence, cameraAngle: angle, subjectFraming: subjectFraming,
            subjectPositioning: subjectPositioning, environmentalDepth: environmentalDepth, errors: errors,
            limitations: limitations, environment: environment, angleComparison: angleComparison,
            scanTiming: scanTiming, modelLoadMs: modelLoadMs)
    }

    /// Attaches a scan's camera-angle result(s) and uses `method`'s result as the camera angle.
    nonisolated func withAngleScan(_ scan: CameraAngleComparison, method: CameraAngleMethod) -> PhotoResult {
        var copy = self
        copy.angleComparison = scan
        return copy.usingCameraAngle(method)
    }
}

// MARK: - GeoCalib → CameraAngleResult

nonisolated enum GeoCalibAngleInterpreter {

    /// GeoCalib's own pitch uncertainty above which the pitch is not reported as a habit.
    static let usablePitchUncertainty = 5.0
    /// Roll uncertainty above which the roll (Dutch angle) is not reported.
    static let usableRollUncertainty = 5.0

    /// Camera angle for the scan mode the user picked. Only that method runs, so scan time
    /// reflects one method (benchmarking). `original` is what the existing pipeline produced;
    /// it is kept only when the mode is `.original`.
    static func scan(_ method: CameraAngleMethod, original: CameraAngleResult, image: CGImage,
                     evidence: PhotoEvidence, models: GeoCalibModels?) -> CameraAngleComparison {
        guard let mode = method.geoCalibMode else {
            return CameraAngleComparison(results: [.original: original],
                                         details: [.original: detail(fromOriginal: original)])
        }

        let selection = SubjectSelector.select(from: evidence.humans.value ?? [])
        let imageSize = CGSize(width: image.width, height: image.height)

        // A camera angle is relative to a subject: no subject, nothing to run.
        guard selection.primary != nil else {
            return CameraAngleComparison(
                results: [method: Self.result(.unknown, roll: nil, .notApplicable(
                    "No usable person was found, so there is no subject to measure the camera angle against."))],
                details: [method: CameraAngleMethodDetail(error: "No subject")])
        }

        let t0 = Date()
        var run: GeoCalibRun?
        var failure: String?
        do {
            let input = try GeoCalibPreprocessor.prepare(cgImage: image)
            let preprocessMs = Date().timeIntervalSince(t0) * 1000
            if let estimator = models?.estimators[mode] {
                do { run = try estimator.estimate(input, preprocessMs: preprocessMs) }
                catch { failure = "GeoCalib could not run: \(error)" }
            } else {
                failure = models?.loadErrors[mode] ?? "The GeoCalib model is not loaded."
            }
        } catch {
            failure = "The photo could not be prepared for GeoCalib (\(error))."
        }
        let (result, detail) = interpret(run: run, failure: failure, method: method,
                                         selection: selection, evidence: evidence, imageSize: imageSize)
        return CameraAngleComparison(results: [method: result], details: [method: detail])
    }

    static func interpret(run: GeoCalibRun?, failure: String?, method: CameraAngleMethod,
                          selection: SubjectSelection, evidence: PhotoEvidence,
                          imageSize: CGSize) -> (CameraAngleResult, CameraAngleMethodDetail) {
        guard let run else {
            let reason = failure ?? "GeoCalib did not run."
            return (result(.unknown, roll: nil, .unavailable(reason)), CameraAngleMethodDetail(error: reason))
        }
        let r = run.result
        var detail = CameraAngleMethodDetail(
            pitchDown: -r.pitch, pitchUncertainty: r.pitchUncertainty,
            roll: r.roll, rollUncertainty: r.rollUncertainty, focalPx: r.focalPx, vfov: r.vfov,
            preprocessMs: run.preprocessMs, predictMs: run.predictMs, optimizeMs: run.optimizeMs)

        let name = "\(method.title) (\(method == .geoCalibHeavy ? "fp32" : "fp16"))"
        let pitchUsable = r.pitchUncertainty.isFinite && r.pitchUncertainty <= usablePitchUncertainty
        let rollUsable = r.rollUncertainty.isFinite && r.rollUncertainty <= usableRollUncertainty
        let rollForResult = rollUsable ? r.roll : nil

        var references = [
            EvidenceReference(source: nil, origin: .rawModelOutput, role: .primary, label: "\(name) camera pitch",
                              value: String(format: "%.1f° %@ (±%.1f°)", abs(r.pitch), r.pitch < 0 ? "down" : "up", r.pitchUncertainty)),
            EvidenceReference(source: nil, origin: .rawModelOutput, role: .contextual, label: "\(name) roll",
                              value: String(format: "%.1f° (±%.1f°)", r.roll, r.rollUncertainty)),
            EvidenceReference(source: nil, origin: .rawModelOutput, role: .contextual, label: "\(name) lens",
                              value: String(format: "vertical field of view %.0f°, focal %.0f px", r.vfov, r.focalPx)),
            EvidenceReference(source: nil, origin: .rawModelOutput, role: .contextual, label: "\(name) time",
                              value: String(format: "%.0f ms network + %.0f ms optimizer (+ %.0f ms shared preprocessing)",
                                            run.predictMs, run.optimizeMs, run.preprocessMs)),
        ]

        // The subject's eye point (same rule as the original method).
        let primaryBox = selection.primary?.box
        let face = primaryBox.flatMap { box in evidence.faces.value.flatMap { SubjectAssociation.face(for: box, among: $0) } }
        let pose = primaryBox.flatMap { box in evidence.pose.value.flatMap { SubjectAssociation.pose(for: box, among: $0) } }
        guard let anchor = SubjectGeometryProvider.observe(pose: pose, face: face).anchor else {
            var out = result(.unknown, roll: rollForResult, .insufficient(
                "\(name) measured the camera tilt, but the subject's eye line could not be located, so the camera's height relative to the subject is unknown.",
                evidence: references))
            out.pitchDownDegrees = pitchUsable ? -r.pitch : nil
            out.dutchAngle = DutchAngleRule.category(rollDegrees: rollForResult)
            return (out, detail)
        }

        // Camera elevation relative to the eyes = −(angle of the eyes above the camera's horizontal plane).
        let W = Double(imageSize.width), H = Double(imageSize.height)
        let eyeX = Double(anchor.eyePoint.x), eyeY = Double(anchor.eyePoint.y)
        let elevation = -r.elevation(x: eyeX * W, y: eyeY * H)
        let sigma = r.pitchUncertainty.isFinite ? r.pitchUncertainty : 90
        detail.cameraElevation = elevation
        detail.cameraElevationUncertainty = sigma
        references.append(EvidenceReference(
            source: nil, origin: .derivedMeasurement, role: .primary, label: "Camera vs eyes",
            value: String(format: "%+.1f° (±%.1f°), eyes from %@", elevation, sigma, anchor.eyeSource)))

        let possible = CameraAngleRule.categories(low: elevation - sigma, high: elevation + sigma)
        let category: CameraAngleCategory = possible.count == 1 ? possible.first! : .unknown

        // Horizon line (where the camera's horizontal plane meets the image), normalised image space.
        let horizon = horizonLine(r, width: W, height: H)
        var heightLevel = CameraHeightLevel.unknown
        var cue: HorizonEyeCue?
        if let horizon {
            let horizonY = horizon.intercept + horizon.slope * eyeX
            cue = HorizonEyeCue(horizon: horizon, eyePoint: anchor.eyePoint, eyeSource: anchor.eyeSource,
                                headHeight: anchor.headHeight, offsetInImageHeights: eyeY - horizonY,
                                offsetInHeadHeights: anchor.headHeight.map { (eyeY - horizonY) / $0 })
            if let pose {
                // The level must not change across the pitch uncertainty.
                let shift = r.focalPx / Double(r.imageHeight) * tan(sigma * .pi / 180)
                let joints = SubjectJointHeights(pose: pose)
                let a = CameraHeightLevelRule.level(horizonY: horizonY - shift, joints: joints)
                let b = CameraHeightLevelRule.level(horizonY: horizonY + shift, joints: joints)
                if a == b { heightLevel = a }
            }
        }

        var quality: EvidenceQuality = sigma <= 2 ? .high : (sigma <= 4 ? .moderate : .low)
        var limitations = [
            "GeoCalib reads the camera's tilt and lens from the whole image; the angle relative to the subject also depends on locating the eyes.",
            "Analysis image is the 1280 px prepared copy, not the original file.",
        ]
        if anchor.isEstimated {
            quality = quality.lowered()
            limitations.append("The eye line was estimated from the face rectangle because eye landmarks were unreliable.")
        }
        if anchor.isUpright == false {
            quality = quality.lowered()
            limitations.append("The subject is not upright (bending, leaning or reclining), so \"high\" and \"low\" angle are less well defined.")
        }

        let headline: String
        switch category {
        case .birdsEye: headline = "The camera is steeply above the subject, looking almost straight down."
        case .highAngle: headline = "The camera is above the subject's eyes, looking down on them."
        case .eyeLevel: headline = "The camera is at about the subject's eye height."
        case .lowAngle: headline = "The camera is below the subject's eyes, looking up at them."
        case .wormsEye: headline = "The camera is steeply below the subject, looking almost straight up."
        case .unknown:
            let words = CameraAngleRule.ordered.filter(possible.contains).map { Self.label($0) }
            headline = "The camera angle is between \(words.joined(separator: " and ")) within GeoCalib's uncertainty, so it is left unknown."
        }
        let explanation = headline + String(
            format: " %@: camera %.0f° %@ the eyes (±%.0f°), phone tilted %.0f° %@, roll %.1f°.",
            name, abs(elevation), elevation >= 0 ? "above" : "below", sigma,
            abs(r.pitch), r.pitch < 0 ? "down" : "up", r.roll)

        let status: AssessmentStatus = category == .unknown ? .insufficientEvidence : .determined
        var out = CameraAngleResult(
            category: category, horizonCue: cue, headPitchDegrees: face?.pitchDegrees, headYawDegrees: face?.yawDegrees,
            imageRollDegrees: rollForResult,
            assessment: Assessment(status: status, quality: status == .determined ? quality : .none,
                                   explanation: explanation, evidence: references, limitations: limitations),
            observations: [],
            decision: CameraAngleDecisionSummary(possibleCategories: possible, contributing: [], conflicts: [],
                                                 notes: [String(format: "Elevation interval %.1f° to %.1f°.", elevation - sigma, elevation + sigma)]),
            sceneLines: [])
        out.elevationDegrees = status == .determined ? elevation : nil
        out.pitchDownDegrees = pitchUsable ? -r.pitch : nil
        out.heightLevel = heightLevel
        out.dutchAngle = DutchAngleRule.category(rollDegrees: rollForResult)
        return (out, detail)
    }

    /// The camera's horizontal plane as a line in normalised image space (y = intercept + slope · x).
    static func horizonLine(_ r: GeoCalibResult, width W: Double, height H: Double) -> HorizonLineFit? {
        let a = r.up[0], b = r.up[1], c = r.up[2]
        guard abs(b) > 1e-6 else { return nil }
        func y(_ x: Double) -> Double { r.cy - r.focalPx * (a * (x - r.cx) / r.focalXPx + c) / b }
        let left = y(0) / H, right = y(W) / H
        return HorizonLineFit(slope: right - left, intercept: left, residualRMS: 0, columnCoverage: 1,
                              lowerRegionLabel: "GeoCalib camera horizon", isOpenWater: false)
    }

    static func detail(fromOriginal a: CameraAngleResult) -> CameraAngleMethodDetail {
        CameraAngleMethodDetail(cameraElevation: a.elevationDegrees, pitchDown: a.pitchDownDegrees,
                                roll: a.imageRollDegrees)
    }

    private static func result(_ category: CameraAngleCategory, roll: Double?, _ assessment: Assessment) -> CameraAngleResult {
        CameraAngleResult(category: category, horizonCue: nil, headPitchDegrees: nil, headYawDegrees: nil,
                          imageRollDegrees: roll, assessment: assessment)
    }

    private static func label(_ c: CameraAngleCategory) -> String {
        switch c {
        case .birdsEye: return "bird's eye"
        case .highAngle: return "high angle"
        case .eyeLevel: return "eye level"
        case .lowAngle: return "low angle"
        case .wormsEye: return "worm's eye"
        case .unknown: return "unknown"
        }
    }
}
