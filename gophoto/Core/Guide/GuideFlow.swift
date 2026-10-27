//
//  GuideFlow.swift
//  gophoto
//
//  Guide variants for testing (picked in the camera's debug panel) and the
//  step-by-step flow of variants B and C. Pure logic: no sensors, no UI.
//
import CoreGraphics
import Foundation

nonisolated enum GuideMode: String, CaseIterable, Identifiable, Sendable {
    /// A: first version. Distance → left/right → up/down (framing) → tilt → straighten. Ring look.
    case current
    /// A, first version with its first look: target rectangle + red/green body outline.
    case currentOldLook
    /// A's order as strict steps with bars and the checklist.
    case currentSteps
    /// Like `currentSteps`, plus the camera-height step before tilt.
    case currentStepsHeight
    /// B: main flow. Distance → camera height → tilt → left/right → straighten.
    case heightFirst
    /// B as first tested on the phone (kept for comparison): distance from head size → body
    /// height → edge cut-off rule, live measurements (no still-phone snapshot), no height cap.
    case heightFirstOld
    /// B + crop: distance (a little wider) → camera height → tilt → rough left/right; the crop
    /// puts the person exactly on the target and rotates a small horizon tilt away.
    case heightFirstCrop
    /// C: like B, but tilt before camera height.
    case tiltFirst
    /// C with B old's rules (live measurements, old distance rule, no height cap).
    case tiltFirstOld
    /// D: baseline without angle guidance. Distance → left/right → up/down → straighten.
    case noAngle
    /// E: fixed rules from the analysis, measured live only where stable (sensor):
    /// framing (full/half body) → phone at a body height (user confirms) → tilt → left/right → straighten.
    case fixedRules
    /// F: stand a little wide, then the photo is cropped to the preset's size and position and
    /// straightened. Guided: room around the person (once) → phone at a body height (once) → tilt.
    case wideCrop

    static let storageKey = "guideMode"

    /// Modes offered in the picker. The others stay in code for reference but are hidden.
    static let visible: [GuideMode] = [.current, .heightFirst, .heightFirstOld, .heightFirstCrop,
                                       .tiltFirst, .tiltFirstOld, .noAngle]

    /// The "old" variants: rules as in the first phone test of B.
    var isOldRules: Bool { self == .heightFirstOld || self == .tiltFirstOld }
    /// Measure distance / camera height / position from the still-phone snapshot (not the old variants).
    var usesSnapshot: Bool { !isOldRules }
    /// Cap the camera-height target at a comfortable reach (not the old variants).
    var capsHeight: Bool { !isOldRules }

    /// The saved mode, or B when nothing (or a hidden mode) is saved.
    static func saved(_ defaults: UserDefaults = .standard) -> GuideMode {
        let mode = defaults.string(forKey: storageKey).flatMap(GuideMode.init(rawValue:))
        return mode.map { visible.contains($0) ? $0 : .heightFirst } ?? .heightFirst
    }

    /// Tilt is set before camera height (C), so moving the phone up/down must keep that tilt.
    var tiltBeforeHeight: Bool {
        guard let tilt = steps.firstIndex(of: .tilt), let height = steps.firstIndex(of: .height) else { return false }
        return tilt < height
    }

    /// Modes whose photo is cropped (and taken at full resolution).
    var crops: Bool { self == .wideCrop || self == .heightFirstCrop }

    /// Size the distance step aims for, relative to the preset. B + crop stands a little
    /// back so the crop has room to move the person left/right.
    var distanceFactor: Double { self == .heightFirstCrop ? 0.85 : 1 }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .current:            "A · Original (ring)"
        case .currentOldLook:     "A · Original (old look)"
        case .currentSteps:       "A · Steps + bars"
        case .currentStepsHeight: "A · Steps + bars + height"
        case .heightFirst: "B · Height first"
        case .heightFirstOld: "B · Old (first test)"
        case .heightFirstCrop: "B · Height first + crop"
        case .tiltFirst:   "C · Tilt first"
        case .tiltFirstOld: "C · Tilt first (old rules)"
        case .noAngle:     "D · No angle"
        case .fixedRules:  "E · Fixed rules"
        case .wideCrop:    "F · Wide + crop"
        }
    }

    /// Step order for the step-by-step modes (B, C). Empty for A and D.
    var steps: [GuideStep] {
        switch self {
        case .heightFirst, .heightFirstOld: [.distance, .height, .tilt, .horizontal, .straight]
        case .heightFirstCrop:    [.distance, .height, .tilt, .horizontal]
        case .tiltFirst, .tiltFirstOld: [.distance, .tilt, .height, .horizontal, .straight]
        case .currentSteps:       [.distance, .horizontal, .vertical, .tilt, .straight]
        case .currentStepsHeight: [.distance, .horizontal, .vertical, .height, .tilt, .straight]
        case .fixedRules:         [.framing, .heightRule, .tilt, .horizontal, .straight]
        case .wideCrop:           [.framing, .heightRule, .tilt]
        case .current, .currentOldLook, .noAngle: []
        }
    }
}

nonisolated enum GuideStep: String, CaseIterable, Sendable {
    case distance, height, tilt, horizontal, vertical, straight
    /// Mode E: full / half body in frame (coarse, no size measuring once done).
    case framing
    /// Mode E: phone held at a body landmark; confirmed by the user, not measured.
    case heightRule

    var title: String {
        switch self {
        case .distance:   "Distance"
        case .height:     "Height"
        case .tilt:       "Tilt"
        case .horizontal: "Left/right"
        case .vertical:   "Up/down"
        case .framing:    "Framing"
        case .heightRule: "Height"
        case .straight:   "Level"
        }
    }
}

/// One step's state in this frame.
nonisolated enum GuideCheck: Equatable, Sendable {
    /// Not measurable, or the preset does not ask for it. The reason is for the debug panel.
    case skipped(String)
    case pending
    case ok
    /// An earlier step is not done yet, so this one is not judged (strict order).
    case locked
}

/// What the guide reads in one frame.
nonisolated struct GuideLive: Sendable {
    var person: CGRect?
    var face: CGRect?
    /// Vertical field of view of the upright frame, degrees.
    var verticalFOV: Double?
    var roll: Double
    /// + = phone tilted down (`DeviceTilt`).
    var pitch: Double
    /// Largest photo the camera can take, megapixels (mode F crop limit).
    var photoMegapixels: Double? = nil
    /// Phone pitch of the frames `person` / `face` come from (a still-phone snapshot).
    /// Used for the camera height so eye position and pitch belong to the same moment.
    var measurePitch: Double? = nil
}

/// What the guide measured and decided in one frame (also shown in the debug panel).
nonisolated struct GuideEvaluation: Equatable, Sendable {
    var instruction: GuideInstruction = .findPerson
    var checks: [GuideStep: GuideCheck] = [:]
    /// The step being fixed now (first unfinished one); nil when everything is OK.
    var activeStep: GuideStep?
    /// True for the modes that fix tilt before camera height (C): the height step uses rings.
    var heightUsesRings = false
    /// "head", "body", or why distance could not be measured.
    var distanceSource = "—"
    /// Live size / target size (> 1 = person too big).
    var sizeRatio: Double?
    /// Face height as an angle now, degrees.
    var headAngle: Double?
    /// Camera height relative to the eyes now and the target, degrees (+ = camera above the eyes).
    var eyeElevation: Double?
    var eyeElevationTarget: Double?
    /// Steps kept done by the latch.
    var latched: Set<GuideStep> = []
    /// Mode E: where to hold the phone — `CameraHeightLevel.rawValue`, or "chestToWaist" (PRD fixed rule).
    var heightRule: String?
    /// Mode E: the framing the preset asks for ("fullBody" / "halfBody"), nil = size only.
    var framingRule: String?
    /// Mode F: the crop the photo will get now (normalized, origin top-left), for the preview.
    var cropWindow: CGRect?
    /// Mode F: smallest allowed person size / target size (from the camera resolution).
    var cropMinScale: Double?
    /// Rough distance to the person, metres (from head or body size), for the height cap.
    var distanceMeters: Double?
    /// The preset's camera height was above what a hand can reach, so the target was lowered.
    var heightCapped = false
}

/// What the step flow remembers between frames.
nonisolated struct GuideProgress: Equatable, Sendable {
    /// Steps done and kept done (latch): not judged again unless they drift far.
    var latched: Set<GuideStep> = []
    /// When each step became OK (seconds, any clock); it latches after `GuideFlow.latchDwell`.
    var okSince: [GuideStep: TimeInterval] = [:]
    /// When the person was lost; the flow starts over after `GuideFlow.lostReset`.
    var lostSince: TimeInterval?
    /// Mode E: the photographer tapped "Done" on the phone-height card.
    var heightConfirmed = false
}

nonisolated enum GuideFlow {

    // Latch: a step that stayed OK this long is kept done, so later steps do not send the
    // guide back over small wobbles. Only a big drift (`breakLimit`) reopens it.
    static let latchDwell = 0.4
    static let lostReset = 2.5

    static func breakLimit(_ step: GuideStep) -> Double {
        switch step {
        case .distance:              0.35   // size ±35%
        case .tilt:                  tiltExit   // degrees: tilt set tight, may drift a little while finding the height
        case .height:                heightExit
        case .horizontal, .vertical: 0.15   // fraction of the frame
        case .straight:              6      // degrees
        case .framing, .heightRule:  .infinity   // discrete: once done, kept until the person is lost
        }
    }

    // Tolerances: enter / exit. A step that is OK uses the looser exit value so it does not flicker.
    static let sizeEnter = 0.15, sizeExit = 0.22
    static let heightEnter = 3.0, heightExit = 5.0
    static let tiltEnter = 2.0, tiltExit = 4.0     // tight first, so the height step reads true
    static let positionEnter = 0.06, positionExit = 0.09
    static let straightEnter = 2.0, straightExit = 3.0

    /// Face at least this tall (frame-height units) → distance from head size; smaller → body height.
    static let minFaceHeight = 0.035
    /// A box within this of the frame edge counts as cut off.
    static let edgeMargin = 0.01
    /// Eyes sit about 40% down a face rectangle (same rule as the photo analysis).
    static let eyeFraction = 0.40

    // Height cap: never ask for the phone higher than a comfortable reach above the eyes.
    /// Highest comfortable phone position above the subject's eyes, metres (photographer about
    /// as tall as the subject, phone still visible). An assumption to test.
    static let maxLiftAboveEyes = 0.30
    /// Typical face-rectangle height and standing body height, metres, for the distance estimate.
    static let faceHeightMeters = 0.20
    static let bodyHeightMeters = 1.65

    /// Step modes (B, C and the "A · Steps" variants).
    /// - Parameters:
    ///   - progress: carried from the previous frame; the updated value is returned.
    ///   - latch: keep finished steps done (see `latchDwell`); false = re-judge every frame.
    ///   - now: seconds on any steady clock.
    static func evaluate(mode: GuideMode, live: GuideLive, analysis: PresetAnalysis?,
                         target: FramingTarget, targetPitch: Double?,
                         progress previous: GuideProgress, latch: Bool,
                         now: TimeInterval) -> (GuideEvaluation, GuideProgress) {
        var result = GuideEvaluation()
        var progress = previous
        guard let person = live.person else {                     // findPerson
            let lost = progress.lostSince ?? now
            if now - lost >= lostReset { progress = GuideProgress() }
            progress.lostSince = lost
            return (result, progress)
        }
        progress.lostSince = nil

        var checks: [GuideStep: GuideCheck] = [:]
        var wanted: [GuideStep: GuideInstruction] = [:]

        func judge(_ step: GuideStep, error: Double, enter: Double, exit: Double,
                   positive: GuideInstruction, negative: GuideInstruction) {
            if latch, progress.latched.contains(step) {
                if abs(error) <= breakLimit(step) { checks[step] = .ok; return }
                progress.latched.remove(step)                       // drifted far: reopen
                progress.okSince[step] = nil
            }
            let limit = progress.okSince[step] != nil ? exit : enter
            if abs(error) <= limit {
                checks[step] = .ok
                let since = progress.okSince[step] ?? now
                progress.okSince[step] = since
                if latch, now - since >= latchDwell { progress.latched.insert(step) }
            } else {
                checks[step] = .pending
                wanted[step] = error > 0 ? positive : negative
                progress.okSince[step] = nil
            }
        }

        // 1. Distance, the same rule as mode A (tested OK on the phone): person box height vs the
        //    preset's box height. The head-size, body-angle and cut-off rules asked people to
        //    stand far too far back, so they are no longer used for the decision; the head
        //    angle is still computed for the debug panel and the distance estimate.
        let liveTop = Double(person.minY) <= edgeMargin, liveBottom = Double(person.maxY) >= 1 - edgeMargin
        if let face = live.face, let vfov = live.verticalFOV {
            result.headAngle = PreferenceAnalyzer.angle(ofHeight: Double(face.height), verticalFOV: vfov)
        }
        if mode.isOldRules {
            // B old: head size when the face is big enough, else body height, else the cut-off rule.
            let refTop = analysis?.clippedTop ?? false, refBottom = analysis?.clippedBottom ?? false
            if let face = live.face, Double(face.height) >= minFaceHeight,
               let head = result.headAngle, let targetHead = analysis?.headAngle, targetHead > 0 {
                result.distanceSource = "head"
                result.sizeRatio = head / targetHead
            } else if liveTop == refTop, liveBottom == refBottom, target.rect.height > 0 {
                result.distanceSource = "body"
                result.sizeRatio = Double(person.height / target.rect.height)
            } else if latch, progress.latched.contains(.distance) {
                result.distanceSource = "latched (edge cut-off changed)"
                checks[.distance] = .ok
            } else if (liveTop && !refTop) || (liveBottom && !refBottom) {
                result.distanceSource = "cut off (photos are not)"
                checks[.distance] = .pending
                wanted[.distance] = .moveFarther
                progress.okSince[.distance] = nil
            } else {
                result.distanceSource = "photos cut off, live not"
                checks[.distance] = .pending
                wanted[.distance] = .moveCloser
                progress.okSince[.distance] = nil
            }
        } else if target.rect.height > 0 {
            // Framing guard: the preset's photos show the whole body at that edge (e.g. full body,
            // feet in frame) but the live person is cut off there, so the box height would read as
            // "too small" and ask to come closer. Step back until the cut edge is free.
            let refTop = analysis?.clippedTop ?? false, refBottom = analysis?.clippedBottom ?? false
            if (liveBottom && !refBottom) || (liveTop && !refTop) {
                result.distanceSource = liveBottom && !refBottom ? "feet cut off (preset is not)" : "head cut off (preset is not)"
                checks[.distance] = .pending
                wanted[.distance] = .moveFarther
                progress.okSince[.distance] = nil
                progress.latched.remove(.distance)
            } else if refBottom, let face = live.face, Double(face.height) >= minFaceHeight,
                      let targetFace = analysis?.faceHeight, targetFace > 0 {
                // Half body (the preset's photos are cut at the bottom): a cut-off box's height is
                // "head to frame edge", not the person's size, so the face's share of the frame sets
                // the distance. A share, not an angle: the reference may be a 2-3× portrait, and
                // matching its angle would send the photographer far back. Sitting does not change it.
                result.distanceSource = "face size (half body)"
                result.sizeRatio = Double(face.height) / targetFace
            } else {
                result.distanceSource = "body (like A)"
                result.sizeRatio = Double(person.height / target.rect.height)
            }
        }
        if let ratio = result.sizeRatio {
            judge(.distance, error: ratio / mode.distanceFactor - 1, enter: sizeEnter, exit: sizeExit,
                  positive: .moveFarther, negative: .moveCloser)
        }

        // Rough distance (metres) from the head, else from an uncut body.
        if let head = result.headAngle, head > 0 {
            result.distanceMeters = faceHeightMeters / (2 * tan(head * .pi / 360))
        } else if !liveTop, !liveBottom, let vfov = live.verticalFOV {
            let body = PreferenceAnalyzer.angle(ofHeight: Double(person.height), verticalFOV: vfov)
            if body > 0 { result.distanceMeters = bodyHeightMeters / (2 * tan(body * .pi / 360)) }
        }

        // B + crop: show where the photo will be cropped (same rule as mode F).
        if mode == .heightFirstCrop, target.rect.height > 0 {
            let minScale = WideCrop.minimumScale(photoMegapixels: live.photoMegapixels)
            let scale = min(WideCrop.maxScale, max(minScale, Double(person.height / target.rect.height)))
            result.cropMinScale = minScale
            result.cropWindow = WideCrop.clamped(WideCrop.window(person: person, target: target.rect, scale: scale))
        }

        // 2. Camera height vs the eyes: eye position + phone pitch + field of view.
        //    Does not depend on tilt: tilting moves the eyes in the frame and changes pitch equally.
        if case .match = analysis?.angle, var targetElevation = analysis?.eyeElevation {
            // Cap: a camera far above the eyes is out of reach; aim for the highest comfortable
            // position instead of asking to raise the phone forever (tilt still matches the preset).
            if mode.capsHeight, let d = result.distanceMeters, d > 0 {
                let reach = atan(maxLiftAboveEyes / d) * 180 / .pi
                if targetElevation > reach {
                    targetElevation = reach
                    result.heightCapped = true
                }
            }
            result.eyeElevationTarget = targetElevation
            if let face = live.face, let vfov = live.verticalFOV, vfov > 0 {
                let focal = 0.5 / tan(vfov * .pi / 360)                 // frame-height units
                let eyeY = Double(face.minY) + Double(face.height) * eyeFraction
                let eyeAboveAxis = atan((0.5 - eyeY) / focal) * 180 / .pi
                let elevation = (live.measurePitch ?? live.pitch) - eyeAboveAxis   // + = camera above the eyes
                result.eyeElevation = elevation
                // When tilt is already done (mode C), say "keep the angle" so the photographer
                // moves the phone up/down instead of tilting it again.
                let tiltFirst = mode.tiltBeforeHeight
                judge(.height, error: elevation - targetElevation, enter: heightEnter, exit: heightExit,
                      positive: tiltFirst ? .lowerPhoneKeepAngle : .lowerPhone,
                      negative: tiltFirst ? .raisePhoneKeepAngle : .raisePhone)
            } else {
                checks[.height] = .skipped("no face")
            }
        } else {
            checks[.height] = .skipped(analysis == nil ? "not analyzed" : "no angle majority")
        }

        // 3. Tilt (phone pitch vs the preset).
        if let targetPitch {
            judge(.tilt, error: live.pitch - targetPitch, enter: tiltEnter, exit: tiltExit,
                  positive: .tiltUp, negative: .tiltDown)
        } else {
            checks[.tilt] = .skipped("no angle majority")
        }

        // 4. Left / right (vertical position follows from height + tilt + distance).
        // Directions are for the PHOTOGRAPHER, same as `GuideInstruction`.
        //    B + crop: loose. The crop moves the person onto the target, so this only asks for
        //    what the crop cannot fix: how far the crop window would run past the frame's side
        //    (then it is pushed back in and the person lands off target). Anywhere the crop can
        //    reach counts as OK; with no room to crop it is the normal ±6%.
        var horizontalError = Double(person.midX - target.rect.midX)
        if mode == .heightFirstCrop, target.rect.height > 0 {
            let minScale = WideCrop.minimumScale(photoMegapixels: live.photoMegapixels)
            let scale = min(WideCrop.maxScale, max(minScale, Double(person.height / target.rect.height)))
            let window = WideCrop.window(person: person, target: target.rect, scale: scale)
            horizontalError = Double(window.minX - WideCrop.clamped(window).minX)
        }
        judge(.horizontal, error: horizontalError,
              enter: positionEnter, exit: positionExit, positive: .moveRight, negative: .moveLeft)

        // 4b. Up / down in the frame (only modes that list `.vertical`; B and C leave it to
        //     height + tilt). + dy = person below the target → move the phone lower.
        judge(.vertical, error: Double(person.midY - target.rect.midY),
              enter: positionEnter, exit: positionExit, positive: .moveLower, negative: .moveHigher)

        // E1. Framing, coarse and discrete (mode E). Full body: nobody cut off and not tiny.
        //     Half body: cut off at the bottom only. Without a framing majority: size ±30%.
        if mode.steps.contains(.framing) {
            result.framingRule = analysis?.framing
            let bodyRatio = target.rect.height > 0 ? Double(person.height / target.rect.height) : 1
            func discrete(_ ok: Bool, _ want: GuideInstruction) {
                if progress.latched.contains(.framing) { checks[.framing] = .ok; return }
                if ok {
                    checks[.framing] = .ok
                    let since = progress.okSince[.framing] ?? now
                    progress.okSince[.framing] = since
                    if now - since >= latchDwell { progress.latched.insert(.framing) }
                } else {
                    checks[.framing] = .pending
                    wanted[.framing] = want
                    progress.okSince[.framing] = nil
                }
            }
            if mode == .wideCrop {
                // F: nobody cut off, not bigger than the preset, not so small the crop gets blurry,
                // and the crop must be able to put the person where the preset has them (left/right).
                let margin: CGFloat = 0.02
                let cut = person.minX <= margin || person.maxX >= 1 - margin
                    || person.minY <= margin || person.maxY >= 1 - margin
                let minScale = WideCrop.minimumScale(photoMegapixels: live.photoMegapixels)
                result.cropMinScale = minScale
                let scale = min(WideCrop.maxScale, max(minScale, bodyRatio))
                let window = WideCrop.window(person: person, target: target.rect, scale: scale)
                result.cropWindow = WideCrop.clamped(window)
                if cut || bodyRatio > WideCrop.maxScale { discrete(false, .moveFarther) }
                else if bodyRatio < minScale { discrete(false, .moveCloser) }
                else if window.minX < 0 { discrete(false, .moveLeft) }
                else if window.maxX > 1 { discrete(false, .moveRight) }
                else { discrete(true, .holdStill) }
            } else {
            switch analysis?.framing {
            case "fullBody":
                if liveTop || liveBottom { discrete(false, .moveFarther) }
                else { discrete(bodyRatio >= 0.7, .moveCloser) }
            case "halfBody":
                if liveTop { discrete(false, .moveFarther) }
                else { discrete(liveBottom, .moveCloser) }
            default:
                discrete(abs(bodyRatio - 1) <= 0.3, bodyRatio > 1 ? .moveFarther : .moveCloser)
            }
            }
        }

        // E2. Phone height at a body landmark (mode E): shown, confirmed by the user, never measured.
        if mode.steps.contains(.heightRule) {
            let rule = analysis?.heightLevel ?? (analysis?.framing == "fullBody" || analysis == nil ? "chestToWaist" : nil)
            result.heightRule = rule
            if rule == nil {
                checks[.heightRule] = .skipped("no height majority")
            } else if progress.heightConfirmed {
                checks[.heightRule] = .ok
            } else {
                checks[.heightRule] = .pending
                wanted[.heightRule] = .setPhoneHeight
            }
        }

        // 5. Phone straight.
        judge(.straight, error: live.roll, enter: straightEnter, exit: straightExit,
              positive: .straighten, negative: .straighten)

        // Strict order: nothing after the first unfinished step is judged or shown as done.
        if let first = mode.steps.firstIndex(where: { checks[$0] == .pending }) {
            for step in mode.steps[(first + 1)...] {
                if case .skipped = checks[step] { continue }
                if latch, progress.latched.contains(step) { continue }   // stays done
                checks[step] = .locked
            }
        }

        // Camera height as a phone puck + slot (not a bar) in every mode with a height step (B, C).
        result.heightUsesRings = mode.steps.contains(.height)
        result.checks = checks
        result.activeStep = mode.steps.first { checks[$0] == .pending }
        result.instruction = mode.steps.first { checks[$0] == .pending }.flatMap { wanted[$0] } ?? .holdStill
        result.latched = progress.latched
        return (result, progress)
    }
}
