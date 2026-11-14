//
//  PhasedEngine.swift
//  gophoto
//
//  Phased guide state machine, shared by the four Phased variants. The variants differ only in
//  `FramingPolicy` (crop / no crop) and in the depth evidence passed in `PhasedFrame.depth`.
//  Pure logic: call `step` with each update; it returns the decision and the events to log.
//
//  Rules (spec §3, §6, §9):
//  - one phase at a time; a finished phase stays finished unless consistent evidence says the
//    final photo can no longer work (reopen, with the reason logged);
//  - decisions read medians over a time window; instructions start / reverse / complete slowly,
//    a movement instruction stops quickly (no overshoot) and is withdrawn when evidence is stale;
//  - face size never drives the distance; tilt and temporary cuts never reopen the distance;
//    raw depth alone never reopens it either;
//  - a phase that cannot be measured is never marked done; an unavailable target is reported.
//
import CoreGraphics
import Foundation

nonisolated struct PhasedEngine: Sendable {

    enum ZoomPlan: String, Sendable {
        /// 1× for the whole guide (Auto crop shoots 48 MP at 1×; depth stays at 1×).
        case fixedOne
        /// No crop: 1× or 2× (only when 2× is a lens / sensor-crop zoom), chosen once in phase 0.
        case oneOrTwo
    }

    let params: PhasedParameters
    let policy: FramingPolicy
    let zoomPlan: ZoomPlan
    /// Smallest linear crop scale allowed (Auto crop quality floor).
    let cropMinScale: Double
    /// Auto crop: the photo's shape (3:4 = the full frame, 9:16 = a centred band). Changes with
    /// the camera's ratio picker, without restarting the guide.
    var cropShape: PhasedCropShape = .fullFrame
    let band: SizeBand
    private(set) var target: PhasedTarget?
    private(set) var targetProblem: String?

    // State
    private(set) var phase: PhasedPhase = .acquire
    private(set) var chosenZoom: Double?
    private(set) var vantageUnavailable: String?
    private(set) var distanceUnavailable: String?
    /// Saved when the distance phase finished: its size, band, zoom and depth at that moment.
    private(set) var distanceLock: (r: Double, zoom: Double?, depth: Double?, time: TimeInterval)?
    private var instruction: PhasedInstruction?
    private var lastDetection: TimeInterval = -1

    // Evidence
    private var size = TimedSamples()
    private var sizeCutTop = TimedSamples()      // 1 = cut, 0 = not
    private var sizeCutBottom = TimedSamples()
    private var spanTop = TimedSamples()
    private var spanBottom = TimedSamples()
    private var midX = TimedSamples()
    private var vantage = TimedSamples()
    /// 12 Nov: face height (frame units) of each vantage reading — the "faces" unit.
    private var faceUnits = TimedSamples()
    /// 12 Nov (log 16:15): the unit is locked when the vantage phase ends. A hand over the face shrank the face
    /// box 24% during tilt, and the same camera height read −0.08 → −0.82 faces. After the lock the unit only
    /// follows the body size (distance), not the face box.
    private(set) var faceUnitLock: (faceHeight: Double, r: Double?)?
    private var pitchSamples = TimedSamples()
    private var rollSamples = TimedSamples()
    private var depth = TimedSamples()
    private var lastSpanSource = "—"
    /// Where the vantage samples come from: "face" or "head + shoulders".
    private(set) var vantageSource = "—"
    private var lastFaceAt: TimeInterval = -.infinity
    private var lastSpanQuality: PhasedMeasure.SpanQuality?

    // Dwell timers
    private var wantDwell = Dwell()
    private var wanted: PhasedInstruction?
    /// When the current instruction appeared, and when each instruction was last withdrawn.
    private var shownSince: TimeInterval?
    /// The movement being watched for progress: its best |error| and when it last improved.
    private var stuck: (instruction: PhasedInstruction, best: Double, since: TimeInterval)?
    /// Phone height accepted at the user's limit: the error then (drift is measured from it).
    private(set) var vantageAccepted: Double?
    /// Tilt accepted at the user's limit: framing does not reopen it.
    private(set) var tiltAccepted = false
    /// Sideways framing accepted at the user's limit (11 Nov).
    private(set) var panAccepted = false
    /// 12 Nov: roll 2–5° asked to straighten; accepted at the user's limit like tilt (own tracker: the pan
    /// check resets the shared `stuck` every update).
    private(set) var rollAccepted = false
    private var rollStuck: (best: Double, since: TimeInterval)?
    private var stoppedAt: [PhasedInstruction: TimeInterval] = [:]
    private var doneDwell = Dwell()
    private var reopenDistanceDwell = Dwell()
    private var reopenVantageDwell = Dwell()
    private var reopenTiltDwell = Dwell()
    private var reopenFitDwell = Dwell()

    init(params: PhasedParameters = .standard, policy: FramingPolicy, zoomPlan: ZoomPlan, cropMinScale: Double) {
        self.params = params
        self.policy = policy
        self.zoomPlan = zoomPlan
        self.cropMinScale = cropMinScale
        self.band = params.sizeBand(policy, cropMinScale: cropMinScale)
    }

    /// New target (shot size, posture or preset changed): every phase that depends on it restarts.
    mutating func setTarget(_ target: PhasedTarget?, problem: String?) -> [PhasedEvent] {
        guard target != self.target || problem != targetProblem else { return [] }
        self.target = target
        self.targetProblem = problem
        restart(from: .acquire)
        return [PhasedEvent(kind: "target", detail: target.map { "shot \($0.shot.rawValue)\($0.sitting ? " (sitting)" : "")" } ?? (problem ?? "none"))]
    }

    /// Back to `phase`: the evidence and the later phases are dropped (the zoom choice is kept
    /// unless the guide starts over).
    private mutating func restart(from phase: PhasedPhase) {
        self.phase = phase
        if phase == .acquire { chosenZoom = nil; distanceUnavailable = nil }
        if phase.number <= PhasedPhase.distance.number { distanceLock = nil }
        if phase.number <= PhasedPhase.vantage.number { vantageUnavailable = nil; vantageAccepted = nil; faceUnitLock = nil }
        if phase.number <= PhasedPhase.tilt.number { tiltAccepted = false }
        panAccepted = false
        rollAccepted = false
        rollStuck = nil
        stuck = nil
        instruction = nil
        wanted = nil
        wantDwell.reset(); doneDwell.reset()
        reopenDistanceDwell.reset(); reopenVantageDwell.reset(); reopenTiltDwell.reset()
        if phase == .acquire {
            size.removeAll(); sizeCutTop.removeAll(); sizeCutBottom.removeAll()
            spanTop.removeAll(); spanBottom.removeAll(); midX.removeAll()
            vantage.removeAll(); depth.removeAll(); faceUnits.removeAll()
        }
    }

    /// The subject changed (another person tapped, identity lost for good): start over.
    mutating func subjectChanged() -> [PhasedEvent] {
        restart(from: .acquire)
        return [PhasedEvent(kind: "subject", detail: "new subject: guide starts over")]
    }

    // MARK: - Step

    mutating func step(_ frame: PhasedFrame) -> (PhasedOutput, [PhasedEvent]) {
        var events: [PhasedEvent] = []
        var out = PhasedOutput()
        let now = frame.time
        out.limitation = targetProblem
        guard let target else {
            out.phase = phase
            out.reason = targetProblem ?? "no target"
            return (out, events)
        }

        record(frame, target: target, now: now)
        if frame.pitch == nil { out.notEvaluated.append("phone pitch / roll missing: phone height and tilt not evaluated") }
        if frame.verticalFOV == nil { out.notEvaluated.append("field of view missing: eye line vs horizon not measurable") }

        // Zoom plan (phase 0 only): the zoom never moves against the photographer later.
        if phase == .acquire { decideZoom(frame, target: target, now: now, events: &events) }
        out.zoomRequest = chosenZoom

        let rMed = size.median(now: now, window: params.window, minCount: params.minSamples)
        let rQuick = size.median(now: now, window: params.quickWindow, minCount: 2)
        let cutTop = (sizeCutTop.median(now: now, window: params.window, minCount: params.minSamples) ?? 0) > 0.5
        let cutBottom = (sizeCutBottom.median(now: now, window: params.window, minCount: params.minSamples) ?? 0) > 0.5
        let fresh = size.newest.map { now - $0 <= params.staleAfter } ?? false
        out.sizeRatio = rMed
        out.sizeSource = lastSpanSource + (lastSpanQuality.map { " · \($0.rawValue)" } ?? "")

        // Later phases: is the distance still workable? (reopen only on consistent evidence)
        if phase.number > PhasedPhase.distance.number, distanceUnavailable == nil {
            if let reason = distanceBroken(now: now, target: target) {
                events.append(PhasedEvent(kind: "reopen", detail: "distance: " + reason,
                                          values: ["r": rMed ?? -1]))
                restart(from: .distance)
            }
        }

        var want: PhasedInstruction?
        var done = false
        var reason = ""

        switch phase {
        case .acquire:
            // Enough readings at the chosen zoom → distance. A person too big to fit is told to
            // step back right away (no deadlock waiting for a whole silhouette).
            let readable = target.span == nil
                ? frame.subject != nil
                : size.coverage(now: now, window: params.window) >= params.window * 0.5 && rMed != nil
            if let chosen = chosenZoom, let zoom = frame.zoom, abs(zoom - chosen) / chosen < 0.03, frame.zoomStable,
               readable {
                advance(to: .distance, "subject readable", events: &events)
            } else if cutTop && cutBottom, target.shot == .full {
                want = .moveBack; reason = "person does not fit (both ends cut)"
            } else {
                reason = target.span == nil ? "no reference size" : "reading the subject"
            }
        case .distance:
            guard target.span != nil else {
                distanceUnavailable = "no reference size (subject box) in the preset"
                advance(to: .vantage, "distance unavailable", events: &events)
                break
            }
            let r = rMed
            let lowerBound = lastSpanQuality == .lowerBound
            let band = shotBand(target)
            if !fresh {
                reason = "no recent size reading"
            } else if let r {
                // Hysteresis: while a move is asked for, it ends inside the ENTER band; without one, a
                // reading must leave the wider EXIT band to start a move (no blinking at the edge).
                // 12 Nov: a move ends `distanceAim` inside the enter band (2 m edge → stop at 2.2 m), when the band
                // is wide enough for that (Auto crop); otherwise at the enter band as before.
                let moving = instruction == .moveBack || instruction == .moveCloser
                let aim = target.shot == .full ? params.distanceAimFull
                        : (target.shot == .threeQuarter ? params.distanceAimThreeQuarter : params.distanceAim)
                let roomy = band.enterHigh / band.enterLow >= aim * aim
                let aimHigh = roomy ? band.enterHigh / aim : band.enterHigh
                let aimLow = roomy ? band.enterLow * aim : band.enterLow
                let inside = moving ? (r >= aimLow && r <= aimHigh)
                                    : (r >= band.exitLow && r <= band.exitHigh)
                let high = moving ? aimHigh : band.exitHigh
                let low = moving ? aimLow : band.exitLow
                if lowerBound, r > band.exitHigh {
                    want = .moveBack; reason = "cut and already larger than the band"
                } else if lowerBound, target.shot == .full {
                    // One end cut, size not certain: aim to see it (local help, not a reset) — unless
                    // the other end is already at the frame edge: no tilt can show both → step back.
                    let m = params.margins(target.shot, policy)
                    let top = spanTop.median(now: now, window: params.quickWindow, minCount: 2)
                    let bottom = spanBottom.median(now: now, window: params.quickWindow, minCount: 2)
                    let noRoom = cutTop ? (bottom.map { 1 - m.bottom - $0 < params.edgeRoom } ?? false)
                                        : (top.map { $0 - m.top < params.edgeRoom } ?? false)
                    // 13 Nov: phone already near the reference pitch → the person is too close, not mis-aimed.
                    // Tilting to see the feet now meant tilting back in the tilt phase and cutting them again.
                    let pitchNow = pitchSamples.median(now: now, window: params.quickWindow, minCount: 2)
                    let nearLevel = pitchNow.map { abs($0 - (target.pitch ?? 0)) <= params.cutTiltBeyond } ?? false
                    if noRoom {
                        want = .moveBack; reason = "cut at the \(cutTop ? "top" : "bottom"), no room to tilt"
                    } else if nearLevel {
                        want = .moveBack; reason = "cut at the \(cutTop ? "top" : "bottom"), phone near the reference pitch"
                    } else {
                        want = cutTop ? .tiltUp : .tiltDown; reason = "person cut at the \(cutTop ? "top" : "bottom")"
                    }
                } else if r > high {
                    want = .moveBack; reason = String(format: "r %.2f > %.2f", r, high)
                } else if r < low {
                    want = .moveCloser; reason = String(format: "r %.2f < %.2f", r, low)
                } else {
                    reason = String(format: "r %.2f in band", r)
                }
                // Stop a movement quickly once the short window is inside (no overshoot).
                if let current = instruction, let q = rQuick {
                    if current == .moveCloser, q >= aimLow { want = nil; reason = "stop: close enough" }
                    if current == .moveBack, q <= aimHigh { want = nil; reason = "stop: far enough" }
                }
                done = inside && !lowerBound && !(target.shot == .full && (cutTop || cutBottom))
                // Room for the final framing: person + headroom + bottom room must fit (else tilt
                // could never finish later).
                if done, let overflow = fitOverflow(now: now, target: target), overflow > 0 {
                    done = false
                    want = .moveBack
                    reason = String(format: "needs room for the final framing (%.0f%% too tall)", overflow * 100)
                }
            } else {
                reason = "size not measurable"
            }
            if complete(done, now: now) {
                distanceLock = (rMed ?? 0, frame.zoom, depth.median(now: now, window: params.window, minCount: 3), now)
                advance(to: .vantage, String(format: "distance done r %.2f", rMed ?? 0), events: &events)
                want = nil
            }
        case .vantage:
            let error = vantageError(now: now, window: params.window)
            out.vantageError = error?.value
            out.vantageUnit = error?.unit ?? "faces"
            out.vantageSource = vantageSource
            if target.vantageFaces == nil && target.vantageDegrees == nil {
                vantageUnavailable = "no phone-height target in the preset (eyeOffsetFaces / eyeElevation missing)"
                advance(to: .tilt, "vantage unavailable", events: &events)
                break
            }
            if let error, isFresh(vantage, now: now) {
                let enter = error.enter, exit = error.exit
                // Same hysteresis as the distance: start beyond EXIT, finish inside ENTER.
                let moving = instruction == .lowerPhone || instruction == .raisePhone
                let limit = moving ? enter : exit
                if error.value > limit { want = .lowerPhone }
                else if error.value < -limit { want = .raisePhone }
                if let current = instruction, let q = vantageError(now: now, window: params.quickWindow, minCount: 2) {
                    if current == .lowerPhone, q.value <= enter * 0.75 { want = nil }
                    if current == .raisePhone, q.value >= -enter * 0.75 { want = nil }
                }
                done = abs(error.value) <= limit && want == nil
                reason = String(format: "%@ %+.2f", error.unit, error.value)
                if stuckAtLimit(want, error: error.value, minStep: error.unit == "faces" ? 0.2 : 2, now: now) {
                    vantageAccepted = error.value
                    advance(to: .tilt, String(format: "vantage accepted at the limit (%@ %+.2f, no progress %.0f s)",
                                              error.unit, error.value, params.stuckAfter), events: &events)
                    want = nil
                    break
                }
            } else {
                reason = "eye line not readable (face / field of view)"
            }
            if complete(done, now: now) {
                advance(to: .tilt, "vantage done", events: &events)
                want = nil
            }
        case .tilt:
            checkVantageDrift(now: now, events: &events)
            guard phase == .tilt else { break }
            // No tilt can make the person + room fit: that is a distance problem, not a tilt one.
            if reopenFitDwell.update((fitOverflow(now: now, target: target) ?? 0) > 0, now: now) >= params.completeDwell {
                events.append(PhasedEvent(kind: "reopen", detail: "distance: person + room do not fit at any tilt"))
                restart(from: .distance)
                break
            }
            // Hysteresis: without a tilt instruction the looser limits apply (a reading at the edge does
            // not start one); while tilting, the person is brought fully inside.
            let tilting = instruction == .tiltUp || instruction == .tiltDown
            let t = tiltWant(frame, target: target, now: now, exitOnly: !tilting)
            out.tiltError = t.error
            out.tiltSource = t.source
            out.tiltNeed = t.need
            want = t.want
            reason = t.reason
            done = t.ok
            if stuckAtLimit(want, error: t.error, minStep: t.source == "pitch" ? 1 : 0.01, now: now) {
                tiltAccepted = true
                advance(to: .framing, String(format: "tilt accepted at the limit (%@ %+.2f, no progress %.0f s)",
                                             t.source, t.error ?? 0, params.stuckAfter), events: &events)
                want = nil
                break
            }
            if complete(done, now: now) {
                advance(to: .framing, "tilt done", events: &events)
                want = nil
            }
        case .framing:
            checkVantageDrift(now: now, events: &events)
            guard phase == .framing else { break }
            let t = tiltWant(frame, target: target, now: now, exitOnly: true)
            out.tiltError = t.error
            out.tiltSource = t.source
            out.tiltNeed = t.need
            let stillOK = t.ok || t.want == nil || tiltAccepted
            if reopenTiltDwell.update(!stillOK, now: now) >= params.reopenDwell {
                events.append(PhasedEvent(kind: "reopen", detail: "tilt: " + t.reason))
                restart(from: .tilt)
                break
            }
            var floorLimited = false
            var panWant: PhasedInstruction?
            if policy == .autoCrop {
                if let crop = finalCrop(now: now, target: target) {
                    floorLimited = crop.floorLimited
                    out.cropWindow = crop.rect
                    // 11 Nov: the crop had to be pushed sideways to stay in the frame → the person would end
                    // nearer the centre than in the reference. Ask to turn the phone (hysteresis: start beyond
                    // `panEnter`, stop at `panExit`); accepted at the user's limit like tilt.
                    let panning = instruction == .moveLeft || instruction == .moveRight
                    let panLimit = panning ? params.panExit : params.panEnter
                    // 12 Nov: also when the crop sits far to one side of the sensor (person near a frame edge):
                    // turn toward the person so the crop is near the middle (crop < 0.5 → person on the left →
                    // "Move the phone left" slides them right).
                    let centreOffset = Double(crop.rect.midX) - 0.5
                    let centreLimit = panning ? params.panCentreExit : params.panCentreEnter
                    var panError = crop.horizontalShift
                    if !panAccepted, abs(crop.horizontalShift) > panLimit {
                        panWant = crop.horizontalShift < 0 ? .moveLeft : .moveRight
                    } else if !panAccepted, abs(centreOffset) > centreLimit {
                        panWant = centreOffset < 0 ? .moveLeft : .moveRight
                        panError = centreOffset
                    }
                    if stuckAtLimit(panWant, error: panError, minStep: 0.01, now: now) {
                        panAccepted = true
                        events.append(PhasedEvent(kind: "accept", detail: String(format: "pan accepted at the limit (shift %+.2f)", crop.horizontalShift)))
                        panWant = nil
                    }
                    let roll = -(frame.roll ?? 0)
                    if abs(roll) >= 0.5, abs(roll) <= params.rollCropReach,
                       PhasedMeasure.fitsRotated(crop.rect, degrees: roll, aspect: frame.frameAspect) {
                        out.cropRoll = roll
                    }
                    reason = String(format: "crop %.0f%%%@ · side %+.2f · centre %+.2f", crop.rect.height * 100,
                                    crop.floorLimited ? " (floor)" : "", crop.horizontalShift, centreOffset)
                } else {
                    reason = "no valid crop now"
                }
            } else {
                reason = "framed in camera"
            }
            // 12 Nov: horizon. 0–2° the crop straightens it; 2–5° ask (until ≤ `rollStop`); > 5° leave it.
            var rollWant: PhasedInstruction?
            // Median roll (not one reading) and a margin above the crop's reach: no ready flicker at the edge.
            if let roll = rollSamples.median(now: now, window: params.window, minCount: 3), !rollAccepted {
                let a = abs(roll)
                let leveling = instruction == .levelPhone
                if a <= params.rollAskMax, a > (leveling ? params.rollStop : params.maxCropRoll + params.rollAskMargin) {
                    rollWant = .levelPhone
                }
                if rollWant != nil, leveling {
                    if var s = rollStuck {
                        if s.best - a >= max(s.best * params.stuckProgress, 0.3) { s.best = a; s.since = now }
                        rollStuck = s
                        if now - s.since >= params.stuckAfter {
                            rollAccepted = true
                            rollWant = nil
                            events.append(PhasedEvent(kind: "accept", detail: String(format: "roll accepted at the limit (%.1f°)", roll)))
                        }
                    } else {
                        rollStuck = (a, now)
                    }
                } else if rollWant == nil {
                    rollStuck = nil
                }
                if rollWant != nil { reason += String(format: " · roll %+.1f°", roll) }
            }
            out.ready = vantageUnavailable == nil && distanceUnavailable == nil && (t.ok || tiltAccepted)
                && (policy == .noCrop || (out.cropWindow != nil && !floorLimited)) && fresh && panWant == nil
                && rollWant == nil
            if out.ready { want = .takePhoto } else if let panWant { want = panWant } else if let rollWant { want = rollWant }
        }

        // Right now, only holding is needed: green "Hold it there" while the phase completes.
        if want == nil, done, doneDwell.since != nil, phase != .framing, phase != .acquire {
            want = .holdIt
        }
        // A crop for the shutter at any time (also before "ready": shaky hands still get a framed
        // photo); only the geometry valid now.
        if policy == .autoCrop, phase != .acquire, let crop = finalCrop(now: now, target: target) {
            out.captureCrop = crop.rect
            let roll = -(frame.roll ?? 0)
            if abs(roll) >= 0.5, abs(roll) <= params.rollCropReach,
               PhasedMeasure.fitsRotated(crop.rect, degrees: roll, aspect: frame.frameAspect) {
                out.captureRoll = roll
            }
        }
        let shown = shotBand(target)
        out.sizeEnterLow = shown.enterLow
        out.sizeEnterHigh = shown.enterHigh

        // Instructions: a new direction must persist `startDwell`; stopping is quick, but a shown
        // instruction stays at least `minShow`, and the same one does not come back within
        // `restartCooldown` of being stopped (no blinking when the reading hovers at a limit).
        let previous = instruction
        if want == .takePhoto || want == .holdIt || want == nil {
            let movement = instruction != nil && instruction != .takePhoto && instruction != .holdIt
            let young = shownSince.map { now - $0 < params.minShow } ?? false
            let holdYoung = shownSince.map { now - $0 < params.holdMinShow } ?? false
            if want == nil, movement, young, fresh {
                // keep it a moment longer
            } else if want == nil, instruction == .holdIt, holdYoung, fresh {
                // the green "Hold it there" does not blink off on one reading
            } else {
                instruction = want
            }
            wantDwell.reset(); wanted = nil
        } else if want == instruction {
            wantDwell.reset(); wanted = nil
        } else {
            if want != wanted { wanted = want; wantDwell.reset() }
            let cooling = want.flatMap { stoppedAt[$0] }.map { now - $0 < params.restartCooldown } ?? false
            if wantDwell.update(true, now: now) >= params.startDwell, !cooling {
                if instruction != nil {
                    events.append(PhasedEvent(kind: "reversal", detail: "\(instruction!.rawValue) → \(want!.rawValue)"))
                }
                instruction = want
                wantDwell.reset(); wanted = nil
            } else if instruction != nil, want != nil {
                // A different direction is building up: withdraw the old one meanwhile.
                instruction = nil
            }
        }
        // Never keep a movement instruction on stale evidence.
        if !fresh, phase == .distance { instruction = nil }
        if instruction != previous {
            if let previous, previous != .takePhoto, previous != .holdIt { stoppedAt[previous] = now }
            shownSince = instruction == nil ? nil : now
        }

        out.phase = phase
        out.instruction = instruction
        out.reason = reason
        if let vantageUnavailable { out.limitation = vantageUnavailable }
        if let distanceUnavailable { out.limitation = distanceUnavailable }
        if out.vantageError == nil, let e = vantageError(now: now, window: params.window) {
            out.vantageError = e.value; out.vantageUnit = e.unit; out.vantageSource = vantageSource
        }
        return (out, events)
    }

    // MARK: - Evidence

    private mutating func record(_ frame: PhasedFrame, target: PhasedTarget, now: TimeInterval) {
        if let pitch = frame.pitch { pitchSamples.append(pitch, at: now) }
        if let roll = frame.roll { rollSamples.append(roll, at: now) }
        guard let subject = frame.subject, let t = frame.detectionTime, t > lastDetection else { return }
        lastDetection = t
        // Frames of a moving zoom (or another zoom than the chosen one) are not comparable.
        guard frame.zoomStable else { return }
        if let chosenZoom, let zoom = frame.zoom, abs(zoom - chosenZoom) / chosenZoom > 0.03 { return }

        if let span = PhasedMeasure.span(subject, shot: target.shot), let ref = target.span, ref > 0 {
            size.append(span.value / ref, at: t)
            sizeCutTop.append(span.cutTop ? 1 : 0, at: t)
            sizeCutBottom.append(span.cutBottom ? 1 : 0, at: t)
            spanTop.append(span.top, at: t)
            spanBottom.append(span.bottom, at: t)
            lastSpanSource = span.source
            lastSpanQuality = span.quality
        }
        midX.append(Double(subject.box.midX), at: t)
        if let fov = frame.verticalFOV, let pitch = frame.pitch, let goal = vantageGoal(target) {
            // Face, or when the eyes are not read (back, looking down, side) the head from the pose:
            // 2/5 from the mask top to the shoulder line. The face wins whenever it reads; the head
            // takes over only after the face has been gone for `headAfterFaceLoss`.
            var faceV: (v: PhasedMeasure.Vantage, unit: Double)?
            if let face = subject.face, Double(face.height) >= params.minFaceHeight,
               let v = PhasedMeasure.vantage(face: face, pitch: pitch, verticalFOV: fov) {
                faceV = (v, Double(face.height))
            }
            var headV: (v: PhasedMeasure.Vantage, unit: Double)?
            if params.headFromPose, PhasedMeasure.eyesUnseen(subject),
               let head = PhasedMeasure.head(subject), head.faceHeight >= params.minFaceHeight,
               let v = PhasedMeasure.vantage(eyeY: head.eyeY, faceHeight: head.faceHeight, pitch: pitch, verticalFOV: fov) {
                headV = (v, head.faceHeight)
            }
            // No face from the start counts from the first reading (also waits 1.5 s).
            if faceV != nil || lastFaceAt == -.infinity { lastFaceAt = t }
            var reading: (v: PhasedMeasure.Vantage, unit: Double, source: String)?
            if let faceV { reading = (faceV.v, faceV.unit, "face") }
            else if let headV, t - lastFaceAt >= params.headAfterFaceLoss { reading = (headV.v, headV.unit, "head + shoulders") }
            if let reading {
                // The two sources differ by a bias: never mix them in one median.
                if reading.source != vantageSource { vantage.removeAll(); vantageSource = reading.source }
                faceUnits.append(reading.unit, at: t)
                var faces = reading.v.faces
                // 12 Nov: after the vantage phase, the locked unit (scaled with the body size when the distance
                // changes) instead of this frame's face box. Same eye-to-horizon distance, steadier unit.
                if let lock = faceUnitLock {
                    var unit = lock.faceHeight
                    if let r0 = lock.r, r0 > 0, let r = size.median(now: t, window: params.quickWindow, minCount: 2) {
                        unit *= r / r0
                    }
                    if unit > 0 { faces = reading.v.faces * reading.unit / unit }
                }
                vantage.append((goal.faces ? faces : reading.v.degrees) - goal.value, at: t)
            }
        }
        if let d = frame.depth, d.validFraction >= 0.3, now - d.time < 0.2 { depth.append(d.value, at: t) }
    }

    /// The vantage target: face units (capped at a comfortable reach) or the angle fallback.
    private func vantageGoal(_ target: PhasedTarget) -> (value: Double, faces: Bool)? {
        if let faces = target.vantageFaces { return (min(faces, params.maxLiftFaces), true) }
        if let degrees = target.vantageDegrees { return (degrees, false) }
        return nil
    }

    private func vantageError(now: TimeInterval, window: TimeInterval, minCount: Int? = nil)
        -> (value: Double, unit: String, enter: Double, exit: Double, reopen: Double)? {
        guard let target, let goal = vantageGoal(target),
              let e = vantage.median(now: now, window: window, minCount: minCount ?? params.minSamples) else { return nil }
        return goal.faces
            ? (e, "faces", params.vantageFacesEnter, params.vantageFacesExit, params.vantageFacesReopen)
            : (e, "degrees", params.vantageDegreesEnter, params.vantageDegreesExit, params.vantageDegreesReopen)
    }

    private func isFresh(_ samples: TimedSamples, now: TimeInterval) -> Bool {
        samples.newest.map { now - $0 <= params.staleAfter } ?? false
    }

    private mutating func complete(_ ok: Bool, now: TimeInterval) -> Bool {
        doneDwell.update(ok, now: now) >= params.completeDwell
    }

    private mutating func advance(to next: PhasedPhase, _ detail: String, events: inout [PhasedEvent]) {
        events.append(PhasedEvent(kind: "phase", detail: "\(phase.rawValue) → \(next.rawValue): \(detail)"))
        if phase == .vantage, next == .tilt,
           let h = faceUnits.median(now: lastDetection, window: params.window, minCount: 3) {
            let r = size.median(now: lastDetection, window: params.window, minCount: 3)
            faceUnitLock = (h, r)
            events.append(PhasedEvent(kind: "lock", detail: String(format: "face unit locked h %.3f r %.2f", h, r ?? -1),
                                      values: ["faceHeight": h, "r": r ?? -1]))
        }
        phase = next
        instruction = nil
        stuck = nil
        wanted = nil
        wantDwell.reset(); doneDwell.reset()
        reopenVantageDwell.reset(); reopenTiltDwell.reset(); reopenDistanceDwell.reset()
    }

    // MARK: - Zoom (phase 0)

    private mutating func decideZoom(_ frame: PhasedFrame, target: PhasedTarget, now: TimeInterval,
                                     events: inout [PhasedEvent]) {
        guard chosenZoom == nil else { return }
        switch zoomPlan {
        case .fixedOne:
            chosenZoom = 1
            events.append(PhasedEvent(kind: "zoom", detail: "1× fixed (\(policy.rawValue))"))
        case .oneOrTwo:
            guard target.span != nil else {
                chosenZoom = 1
                events.append(PhasedEvent(kind: "zoom", detail: "1×: no reference size"))
                return
            }
            // Decide from readings at 1× only.
            guard let zoom = frame.zoom, abs(zoom - 1) < 0.03,
                  let r = size.median(now: now, window: params.window, minCount: params.minSamples) else { return }
            let top = spanTop.median(now: now, window: params.window, minCount: params.minSamples) ?? 0
            let bottom = spanBottom.median(now: now, window: params.window, minCount: params.minSamples) ?? 1
            // At 2× the subject doubles about the frame centre: it must still fit with margins.
            let fitsAtTwo = 0.5 + 2 * (top - 0.5) >= 0.02 && 0.5 + 2 * (bottom - 0.5) <= 0.98
            if r < params.twoXBelow, frame.nativeTwoX, fitsAtTwo || target.shot != .full {
                chosenZoom = 2
                size.removeAll(); sizeCutTop.removeAll(); sizeCutBottom.removeAll()
                spanTop.removeAll(); spanBottom.removeAll(); midX.removeAll(); vantage.removeAll()
                events.append(PhasedEvent(kind: "zoom", detail: "2× (sensor crop): person small at 1×",
                                          values: ["r1x": r]))
            } else {
                chosenZoom = 1
                let why = !frame.nativeTwoX && r < params.twoXBelow ? "2× would be digital" : "1× fits"
                events.append(PhasedEvent(kind: "zoom", detail: "1×: " + why, values: ["r1x": r]))
            }
        }
    }

    // MARK: - At the limit

    /// True once the shown movement `want` has made no progress (|error| not down by
    /// `stuckProgress` of its best) for `stuckAfter`: the user is at a physical limit.
    /// `minStep`: the smallest real progress in the error's unit (reading noise below it does not
    /// reset the timer — log 17:22: faces +0.85 → +0.74 jitter kept "Lower the phone" up 5 s).
    private mutating func stuckAtLimit(_ want: PhasedInstruction?, error: Double?, minStep: Double,
                                       now: TimeInterval) -> Bool {
        guard let want, want == instruction, let error else { stuck = nil; return false }
        let e = abs(error)
        guard var s = stuck, s.instruction == want else {
            stuck = (want, e, now)
            return false
        }
        if s.best - e >= max(s.best * params.stuckProgress, minStep) { s.best = e; s.since = now }
        stuck = s
        return now - s.since >= params.stuckAfter
    }

    /// 13 Nov: the size band for this shot. Full body (Auto crop) closes the near side lower: more room for
    /// feet and head. Other shots: the policy band as before.
    private func shotBand(_ target: PhasedTarget?) -> SizeBand {
        guard policy == .autoCrop, target?.shot == .full else { return band }
        var b = band
        b.enterHigh = min(b.enterHigh, params.fullEnterHigh)
        b.exitHigh = min(b.exitHigh, params.fullExitHigh)
        b.reopenHigh = min(b.reopenHigh, params.fullReopenHigh)
        // Keep the band ordered when a small crop floor already raised the low side.
        b.enterLow = min(b.enterLow, b.enterHigh * 0.8)
        b.exitLow = min(b.exitLow, b.enterLow * 0.94)
        b.reopenLow = min(b.reopenLow, b.exitLow * 0.94)
        return b
    }

    // MARK: - Reopen rules

    /// Why the finished distance cannot give a workable photo any more, or nil. Needs
    /// consistent size evidence over `reopenWindow` for `reopenDwell`; depth (when valid) must
    /// agree; a cut while moving the phone does not count unless both ends are cut.
    private mutating func distanceBroken(now: TimeInterval, target: PhasedTarget) -> String? {
        let r = size.median(now: now, window: params.reopenWindow, minCount: params.minSamples * 2)
        let cutTop = (sizeCutTop.median(now: now, window: params.reopenWindow, minCount: params.minSamples * 2) ?? 0) > 0.5
        let cutBottom = (sizeCutBottom.median(now: now, window: params.reopenWindow, minCount: params.minSamples * 2) ?? 0) > 0.5
        var reason: String?
        let band = shotBand(target)
        if let r, r > band.reopenHigh, lastSpanQuality != .lowerBound || r > band.reopenHigh * 1.1 {
            reason = String(format: "r %.2f > %.2f", r, band.reopenHigh)
        } else if let r, r < band.reopenLow, lastSpanQuality != .lowerBound {
            reason = String(format: "r %.2f < %.2f", r, band.reopenLow)
        } else if target.shot == .full, cutTop, cutBottom {
            reason = "both ends cut"
        }
        // Depth agreement: the size changed, but the subject's depth did not → pose / tilt, not a walk.
        if reason != nil, let lockDepth = distanceLock?.depth, lockDepth > 0,
           let d = depth.median(now: now, window: params.reopenWindow, minCount: 4) {
            let change = d / lockDepth - 1
            if abs(change) < 0.06 { reason = nil }
        }
        if reopenDistanceDwell.update(reason != nil, now: now) >= params.reopenDwell { return reason }
        return nil
    }

    /// The phone height drifted far from the target for long: back to the vantage phase.
    private mutating func checkVantageDrift(now: TimeInterval, events: inout [PhasedEvent]) {
        guard vantageUnavailable == nil,
              let e = vantageError(now: now, window: params.reopenWindow, minCount: params.minSamples * 2) else {
            reopenVantageDwell.reset(); return
        }
        // Accepted at the limit: only a further drift away from that point reopens.
        let drift = abs(e.value - (vantageAccepted ?? 0))
        if reopenVantageDwell.update(drift > e.reopen, now: now) >= params.reopenDwell {
            events.append(PhasedEvent(kind: "reopen", detail: String(format: "vantage: %@ %+.2f", e.unit, e.value)))
            restart(from: .vantage)
        }
    }

    // MARK: - Tilt and final framing

    private struct TiltDecision {
        var want: PhasedInstruction?
        var ok: Bool
        var error: Double?
        var source: String
        var reason: String
        /// Bar value: + = tilt up needed, 1 = at the edge of the tolerance.
        var need: Double? = nil
    }

    /// How much taller than the frame the person + headroom + bottom room are (frame units, > 0 = no
    /// tilt can fit them), from the short window. Nil when not measurable.
    func fitOverflow(now: TimeInterval, target: PhasedTarget) -> Double? {
        let w = params.quickWindow
        guard let top = spanTop.median(now: now, window: w, minCount: 2),
              let bottom = spanBottom.median(now: now, window: w, minCount: 2) else { return nil }
        let m = params.margins(target.shot, policy)
        switch policy {
        case .autoCrop:
            guard let refSpan = target.span, refSpan > 0 else { return nil }
            let c = min(1, max(PhasedMeasure.shapeMinScale(cropMinScale, shape: cropShape), (bottom - top) / refSpan))
            let headroom = (target.top ?? m.top) * c
            return (bottom + m.bottom) - (top - headroom) - 1 - params.cropSlack
        case .noCrop:
            guard target.shot == .full else { return nil }   // cut shots may run past the bottom
            return (bottom - top) + max(m.top, target.top ?? m.top) + m.bottom - 1 - params.cropSlack
        }
    }

    /// Tilt, from the short window (stops as soon as it is right):
    /// 1. feasibility: the person (+ room) inside the frame, or the crop placeable;
    /// 2. No crop: the reference headroom decides (the reference pitch is only logged: with the
    ///    distance and height fixed, the pitch IS the headroom);
    ///    Auto crop: the reference pitch, soft — never pushed past the frame edge on that side.
    private func tiltWant(_ frame: PhasedFrame, target: PhasedTarget, now: TimeInterval,
                          exitOnly: Bool = false) -> TiltDecision {
        let margins = params.margins(target.shot, policy)
        let w = params.quickWindow
        guard let top = spanTop.median(now: now, window: w, minCount: 2),
              let bottom = spanBottom.median(now: now, window: w, minCount: 2) else {
            return TiltDecision(want: nil, ok: false, error: nil, source: "—", reason: "subject not measurable")
        }
        let slack = params.cropSlack
        let unit = params.topExit
        // Auto crop with a crop that can be made: the crop decides feasibility (its own room is
        // margin × crop scale). The raw frame margins only apply without one — they asked for a full
        // 6% frame below the knees at r 0.89 and kept reopening tilt over 0.5% (log 16:56, 3/4).
        let crop = policy == .autoCrop ? finalCrop(now: now, target: target, window: w) : nil
        let rawFit = crop == nil
        // 1. Feasibility.
        if rawFit, top < margins.top - (exitOnly ? slack : 0) {
            return TiltDecision(want: .tiltUp, ok: false, error: top - margins.top, source: "fit",
                                reason: String(format: "top at %.2f, needs %.2f", top, margins.top),
                                need: (margins.top - top) / unit)
        }
        let bottomLimit = 1 - margins.bottom + (exitOnly ? slack : 0)
        let checksBottom = target.shot == .full || policy == .autoCrop
        if rawFit, checksBottom, bottom > bottomLimit {
            return TiltDecision(want: .tiltDown, ok: false, error: bottom - bottomLimit, source: "fit",
                                reason: String(format: "bottom at %.2f, limit %.2f", bottom, bottomLimit),
                                need: -(bottom - bottomLimit) / unit)
        }
        var cropShift = 0.0
        if let crop {
            cropShift = crop.verticalShift
            // Hysteresis: a move starts beyond the slack, and while tilting it ends at 0.
            let shiftLimit = exitOnly ? slack : 0
            if crop.verticalShift < -shiftLimit {
                return TiltDecision(want: .tiltUp, ok: false, error: crop.verticalShift, source: "crop",
                                    reason: "crop would leave the frame at the top", need: -crop.verticalShift / unit)
            }
            if crop.verticalShift > shiftLimit {
                return TiltDecision(want: .tiltDown, ok: false, error: crop.verticalShift, source: "crop",
                                    reason: "crop would leave the frame at the bottom", need: -crop.verticalShift / unit)
            }
        }
        // Room left before a frame edge, per tilt direction (tilting up moves the scene down).
        // With a crop: how far its wanted top can move before it leaves the frame (+ slack).
        let roomUp: Double, roomDown: Double
        if let crop {
            let wantTop = Double(crop.rect.minY) + cropShift
            roomUp = (1 - Double(crop.rect.height)) - wantTop + slack
            roomDown = wantTop + slack
        } else {
            roomUp = checksBottom ? bottomLimit - bottom : 1
            roomDown = top - margins.top
        }

        // 2a. No crop: the reference headroom.
        if policy == .noCrop {
            guard let refTop = target.top else {
                return TiltDecision(want: nil, ok: true, error: nil, source: "fit", reason: "fits", need: 0)
            }
            let error = top - refTop          // + = person lower than in the reference
            let limit = exitOnly ? params.topExit : params.topEnter
            if abs(error) <= limit {
                return TiltDecision(want: nil, ok: true, error: error, source: "headroom",
                                    reason: String(format: "headroom %+.2f", error), need: -error / unit)
            }
            // Tilting down moves the scene up in the frame.
            return TiltDecision(want: error > 0 ? .tiltDown : .tiltUp, ok: false, error: error, source: "headroom",
                                reason: String(format: "headroom %+.2f from the reference", error), need: -error / unit)
        }
        // 2b. Auto crop: the reference pitch, soft. Without a reading it is not evaluated.
        if let goal = target.pitch {
            guard let pitch = pitchSamples.median(now: now, window: params.quickWindow, minCount: 3) else {
                return TiltDecision(want: nil, ok: false, error: nil, source: "pitch", reason: "pitch missing: not evaluated")
            }
            let error = pitch - goal          // + = tilted further down than the reference → tilt up
            let limit = exitOnly ? params.pitchExit : params.pitchEnter
            if abs(error) <= limit {
                return TiltDecision(want: nil, ok: true, error: error, source: "pitch",
                                    reason: String(format: "pitch %+.1f°", error), need: error / limit)
            }
            // Never push the person past the frame edge for the reference pitch: the frame wins.
            let room = error > 0 ? roomUp : roomDown
            let edge = target.shot == .full ? params.edgeRoomFull : params.edgeRoom
            if room < edge {
                return TiltDecision(want: nil, ok: true, error: error, source: "pitch",
                                    reason: String(format: "pitch %+.1f° kept (frame edge)", error), need: 0)
            }
            return TiltDecision(want: error > 0 ? .tiltUp : .tiltDown, ok: false, error: error, source: "pitch",
                                reason: String(format: "pitch %+.1f° from the reference", error), need: error / limit)
        }
        return TiltDecision(want: nil, ok: true, error: nil, source: "fit", reason: "fits", need: 0)
    }

    // MARK: - Test fixture (video replay only)

    /// Replay scenario "distance locked": the subject's current span (median), once the guide is in
    /// the distance phase with enough readings. Nil until then.
    func fixtureBaselineSpan(now: TimeInterval) -> Double? {
        guard phase == .distance,
              let top = spanTop.median(now: now, window: params.window, minCount: params.minSamples),
              let bottom = spanBottom.median(now: now, window: params.window, minCount: params.minSamples),
              bottom > top else { return nil }
        return bottom - top
    }

    /// Replay scenario "distance locked" (SIMULATED STATE, applied once by the replay harness): the
    /// reference size becomes `referenceSpan` and the distance phase is marked done. From then on the
    /// production rules alone decide (they may reopen it). Never used live.
    mutating func seedDistanceFixture(referenceSpan: Double, now: TimeInterval, fixtureID: String) -> [PhasedEvent] {
        guard phase == .distance, var t = target, referenceSpan > 0 else { return [] }
        var events = [PhasedEvent(kind: "fixture", detail: "\(fixtureID): distance marked done (simulated state)",
                                  values: ["referenceSpan": referenceSpan])]
        t.span = referenceSpan
        target = t
        size.removeAll(); sizeCutTop.removeAll(); sizeCutBottom.removeAll()
        distanceLock = (1, chosenZoom, nil, now)
        advance(to: .vantage, "fixture \(fixtureID)", events: &events)
        return events
    }

    /// Auto crop: the crop from the window's median geometry, or nil when it cannot be made.
    func finalCrop(now: TimeInterval, target: PhasedTarget, window: TimeInterval? = nil) -> PhasedMeasure.Crop? {
        let w = window ?? params.window, n = window == nil ? params.minSamples : 2
        guard let top = spanTop.median(now: now, window: w, minCount: n),
              let bottom = spanBottom.median(now: now, window: w, minCount: n),
              let mid = midX.median(now: now, window: w, minCount: n) else { return nil }
        let span = PhasedMeasure.Span(value: bottom - top, top: top, bottom: bottom, quality: .measured,
                                      cutTop: false, cutBottom: false, source: "")
        return PhasedMeasure.crop(span: span, subjectMidX: mid, target: target, minScale: cropMinScale,
                                  shape: cropShape)
    }
}
