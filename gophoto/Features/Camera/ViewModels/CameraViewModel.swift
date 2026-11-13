//
//  CameraViewModel.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//
//  CameraViewModel.swift
//  gophoto
//

import Observation
import AVFoundation
import UIKit
import ImageIO

enum CameraState: Equatable {
    case idle
    case running
    case permissionDenied
    case failed(String)
    case restricted
}

@Observable
final class CameraViewModel {

    // MARK: State the View reads
    private(set) var state: CameraState = .idle
    private(set) var isCapturing = false
    private(set) var errorMessage: String?
    private(set) var horizon: HorizonState = .hidden
    private(set) var captureCount = 0
    private(set) var currentZoomLabel: String?
    /// Where the last shot's time went (debug panel): capture, crop, enhance, save, in seconds.
    private(set) var lastShotTiming: String?

    /// The photo just taken, shown for review with its enhanced version; saved only on Save.
    private(set) var review: CaptureReview?
    private(set) var isSavingReview = false
    /// Drives the review cover; closing it discards the photo (Retake).
    var isReviewing: Bool {
        get { review != nil }
        set { if !newValue { retake() } }
    }
    @ObservationIgnored private let enhancer = PhotoEnhancer()
    @ObservationIgnored private var enhanceTask: Task<Void, Never>?

    // for the guide frame
    private(set) var target: FramingTarget = .center   // from the selected preset's AI analysis
    private(set) var instruction: GuideInstruction = .findPerson
    var isReady: Bool { instruction == .holdStill }      // "green"

    // Live values. Observable so the debug panel can show them; the guide UI does not read them.
    private(set) var personBox: CGRect?                  // normalized, origin top-left
    private(set) var roll: Double = 0                    // + = rotated clockwise
    private(set) var pitch: Double = 0                   // + = phone tilted down
    private(set) var face: CGRect?                       // normalized, origin top-left
    /// Joints the latest live pose saw inside the frame, and when (the pose runs every few
    /// detections). Older than `jointsMaxAge` = unknown, so the body-cut check waits.
    @ObservationIgnored private var visibleJoints: (joints: Set<BodyJoint>, at: TimeInterval)?
    private static let jointsMaxAge: TimeInterval = 1.0

    // Zoom settling: boxes are only comparable within one zoom. While the zoom moves (and a
    // moment after, frames still in flight) automatic zoom waits, and size samples restart.
    @ObservationIgnored private var lastFrameZoom: Double?
    @ObservationIgnored private var zoomQuietSince: TimeInterval?
    private static let zoomSettle: TimeInterval = 0.3
    /// Recent person / face boxes at the current zoom; automatic zoom uses their median.
    @ObservationIgnored private var fovSamples: [(person: CGRect, face: CGRect?)] = []
    /// Automatic zoom decided to change the size and has not finished (guide waits its turn).
    @ObservationIgnored private var zoomSizeChangePending = false
    /// Zoom the body-cut rule zoomed in to; size may not zoom out past it (no ping-pong).
    @ObservationIgnored private var cutFloorZoom: Double?
    /// Zoom moving / settling, or about to change: the distance step waits instead of "walk".
    private var zoomWillHandleSize: Bool {
        adaptiveFOVZoomInFlight || zoomSizeChangePending
            || !zoomSettled(now: clockNow)
    }
    private static let fovSampleCount = 5, fovMinSamples = 3

    /// Tracks the zoom of each frame. Returns true when the zoom changed (samples restart).
    private func recordZoom(_ detection: PersonDetection?, now: TimeInterval) {
        guard let zoom = detection?.zoomFactor else { return }
        let changed = lastFrameZoom.map { abs(zoom - $0) / $0 > 0.01 } ?? false
        lastFrameZoom = zoom
        if changed || detection?.isZooming == true {
            zoomQuietSince = nil
            fovSamples.removeAll()
            if !usesTeamGuide {         // Main (team) kept its snapshot across zoom changes
                stillFrames.removeAll()
                snapshot = nil          // measured at another zoom: start a new one
                snapshotFrames = 0
            }
        } else if zoomQuietSince == nil {
            zoomQuietSince = now
        }
    }

    private func zoomSettled(now: TimeInterval) -> Bool {
        zoomQuietSince.map { now - $0 >= Self.zoomSettle } ?? (lastFrameZoom == nil)
    }
    private(set) var personOutline: CGImage?             // body outline, old-look mode only
    private(set) var exposure: ExposureStatus?           // backlight tip / ISO / shutter (debug panel)
    let lighting = LightingCoordinator()                 // sun / light tips; the camera owns the exposure
    @ObservationIgnored private var verticalFOV: Double? // of the upright frame, degrees
    @ObservationIgnored private var photoMegapixels: Double? // largest photo size (mode F)
    /// Largest photo the active camera can take, megapixels (info sheet).
    var largestPhotoMegapixels: Double? { photoMegapixels }

    // Guide variant under test (debug panel). Saved across launches.
    /// Photo ratio (4:3 native; 1:1 and 16:9 are centred crops of it). Saved across launches.
    var captureAspect: CaptureAspect =
        UserDefaults.standard.string(forKey: CaptureAspect.storageKey).flatMap(CaptureAspect.init(rawValue:)) ?? .fourThree {
        didSet { if savesSetup { UserDefaults.standard.set(captureAspect.rawValue, forKey: CaptureAspect.storageKey) } }
    }
    /// False when the view fixes mode + ratio (testing mode): don't overwrite the developer's saved choice.
    @ObservationIgnored private var savesSetup = true

    var guideMode: GuideMode = GuideMode.saved() {
        didSet {
            if savesSetup { UserDefaults.standard.set(guideMode.rawValue, forKey: GuideMode.storageKey) }
            camera.setOutlineEnabled(guideMode == .currentOldLook)
            camera.setHighResolution(guideMode.crops)
            progress = GuideProgress()
            adaptiveFOVReset()
            updateInstruction()
        }
    }

    // MARK: Experiment (appMode 2): which guide runs, and the framing of the Phased family

    /// Guide + framing under test. appMode 1 fixes Phased · Auto crop (no depth, Blur Off; not saved, no log).
    var experiment = ExperimentSelection(guide: .mainModified, framing: .autoCrop) {
        didSet {
            guard experiment != oldValue else { return }
            experimentChanged(from: oldValue)
        }
    }
    /// True in appMode 2 (developer): the experiment picker, saving and the guide log.
    private(set) var experimentEnabled = false
    /// Main = the team's frozen guide (`TeamGuideFlow`, `TeamAdaptiveFOV`, its ViewModel glue).
    private var usesTeamGuide: Bool { experiment.guide == .main }
    /// One of the Phased guides runs (its own engine; Main's steps, bars and zoom stay off).
    var isPhased: Bool { experiment.guide.isPhased }

    /// A new guide or framing: everything that belonged to the old one is dropped (instructions,
    /// steps, zoom decisions in flight are ignored, snapshot). A capture already taken keeps the
    /// selection it was taken with (`takePhoto` copies it at the shutter).
    private func experimentChanged(from old: ExperimentSelection) {
        if experimentEnabled {
            UserDefaults.standard.set(experiment.guide.rawValue, forKey: ExperimentGuide.storageKey)
            UserDefaults.standard.set(experiment.framing.rawValue, forKey: FramingPolicy.storageKey)
        }
        experimentGeneration += 1
        if let guideLog {
            var f = logBase()
            f["event"] = "selection changed"
            f["fromGuide"] = .string(old.guide.rawValue)
            f.set("fromFraming", old.framingLabel)
            guideLog.log("selection", f)
        }
        progress = GuideProgress()
        evaluation = GuideEvaluation()
        instruction = .findPerson
        adaptiveFOVReset()
        smoothing.removeAll()
        stillFrames.removeAll()
        snapshot = nil
        snapshotFrames = 0
        fovSamples.removeAll()
        experimentDidChange(from: old)
        if isReplay, !replayApplyingBatch { restartReplay(reason: "guide / framing changed") }
        updateInstruction()
    }
    /// Bumped on every guide / framing change: async work started for an older selection
    /// (zoom requests, depth switches) checks it and drops its result.
    @ObservationIgnored private(set) var experimentGeneration = 0

    // MARK: Phased state (logic in the Phased extension at the end of this file)

    /// The Phased engine's decision this update (debug panel, crop window, readiness).
    private(set) var phased = PhasedOutput()
    /// The one instruction shown in Phased: choosing / finding the subject first, then the engine's.
    private(set) var phasedInstruction: PhasedInstruction?
    /// Selection UI: dims everything but people (nil = no dimming).
    private(set) var selectionDimMask: CGImage?
    /// A phase just finished: green confirmation for about a second ("Distance ✓"), else nil.
    private(set) var phasedFlash: String?
    @ObservationIgnored private var phasedFlashID = 0
    /// What this iPhone offers for Phased + Depth (checked once).
    let depthSupport: LiveDepthSupport = CameraService.liveDepthSupport()
    /// Live depth now (Phased + Depth), nil when not requested.
    private(set) var liveDepth: LiveDepthSupport?
    @ObservationIgnored private var phasedEngine: PhasedEngine?
    @ObservationIgnored private var phasedEngineSourceMP: Double?
    @ObservationIgnored private var selector = PhasedSubjectPicker()
    @ObservationIgnored private var phasedCandidates: [CGRect] = []
    @ObservationIgnored private var phasedSubject: SubjectObservation?
    @ObservationIgnored private var phasedDetectionTime: TimeInterval?
    @ObservationIgnored private var phasedLockedBox: CGRect?
    @ObservationIgnored private var phasedSubjectLocked = false
    @ObservationIgnored private var phasedZooming = false
    @ObservationIgnored private var phasedLandmarks: (marks: [BodyLandmark], at: TimeInterval)?
    @ObservationIgnored private var phasedExtent: (box: CGRect, edges: FrameEdges, at: TimeInterval)?
    @ObservationIgnored private var phasedZoomTarget: (zoom: Double, at: TimeInterval)?
    @ObservationIgnored private var dimmingOn = false
    @ObservationIgnored private var lockRequested: CGRect?
    @ObservationIgnored private var latestDepth: DepthSample?

    // MARK: Replay state (appMode 2 testing; logic in the Replay extension at the end of this file)

    /// Frames come from a video instead of the camera.
    private(set) var isReplay = false
    /// Changes with the frame source: the View restarts its observing tasks on it.
    private(set) var sourceID = 0
    @ObservationIgnored private var replayService: ReplayCameraService?
    /// The camera the guide talks to: the replay adapter (also the action sink) while replaying.
    private var camera: CameraServiceProtocol { replayService ?? cameraService }
    /// Media time of the last analysed replay frame: the guide's clock in Replay (stops when paused).
    @ObservationIgnored private var replayClock: TimeInterval?
    private var clockNow: TimeInterval { isReplay ? (replayClock ?? 0) : ProcessInfo.processInfo.systemUptime }
    private(set) var replayInfo: ReplayVideoInfo?
    private(set) var replayImage: CGImage?
    private(set) var replayTime: Double = 0
    private(set) var replayPlaying = false
    private(set) var replayEnded = false
    /// Test scenario; changing it starts a new run.
    var replayScenario: ReplayScenario = .rgbObservation {
        didSet { if replayScenario != oldValue, !replayApplyingBatch { restartReplay(reason: "scenario changed") } }
    }
    private(set) var replayRunNumber = 0
    /// Files to share after a run ended (run JSON, summary CSV, guide log, test frames).
    private(set) var replayExports: [URL] = []
    private(set) var replayMessage: String?
    /// Main / Main modified in Replay: steps after distance need sensors a video lacks → hidden.
    private(set) var replayMaskNote: String?
    @ObservationIgnored private var replayRecorder: ReplayRunRecorder?
    @ObservationIgnored private var replaySeeded = false
    @ObservationIgnored private var replayBaseline: [(box: CGRect, face: Double?)] = []
    @ObservationIgnored private var replayBaselineSince: TimeInterval?
    @ObservationIgnored private var replayFixtureSpan: (span: Double, shot: PhasedShot, sitting: Bool)?
    @ObservationIgnored private var replayMainFixture: (box: CGRect, face: Double?)?
    @ObservationIgnored private var replaySubjectSeen: Bool?
    @ObservationIgnored private var replayEverLocked = false
    /// "Run all": the remaining combinations; nil = no batch.
    @ObservationIgnored private var replayBatch: ReplayBatchPlan?
    /// Batch progress for the controls ("Run all 3/12 · …"), nil when no batch runs.
    private(set) var replayBatchStatus: String?
    /// The batch is switching guide / shot / scenario: no extra runs for those changes.
    @ObservationIgnored private var replayApplyingBatch = false

    // MARK: Adaptive FOV state

    @ObservationIgnored private var adaptiveFOVTargetZoom: Double? = nil
    @ObservationIgnored private var adaptiveFOVLastAppliedZoom: Double? = nil
    @ObservationIgnored private var adaptiveFOVLastChangeTime: TimeInterval? = nil
    @ObservationIgnored private var adaptiveFOVHoldSince: TimeInterval? = nil
    @ObservationIgnored private var adaptiveFOVWasHold: Bool = false
    /// Nobody detected: grace period, then back to the 1.0x baseline (replaces the old freeze).
    @ObservationIgnored private var personLoss = PersonLossZoomReset()
    @ObservationIgnored private var adaptiveFOVZoomInFlight = false
    @ObservationIgnored private var liveEnvironmentSignal: LiveEnvironmentSignal?

    private static let adaptiveFOVMaxRatePerSecond: Double = 0.5
    private static let adaptiveFOVHysteresisDeadband: Double = 0.10
    @ObservationIgnored private var adaptiveFOVStatusTask: Task<Void, Never>? = nil
    private(set) var adaptiveFOVStatusText: String? = nil

    /// Steps, checks and measurements of the current frame (modes B and C fill the checks).
    private(set) var evaluation = GuideEvaluation()
    @ObservationIgnored private var progress = GuideProgress()
    /// Keep finished steps done (no going back over small wobbles). Debug-panel toggle.
    /// Developer mode only (temporary): also save a copy with the background blurred at half
    /// strength (`BokehProcessor`). Off by default; the original is always saved.
    var bokehEnabled = false {
        didSet {
            guard bokehEnabled != oldValue else { return }
            // On: the dual / triple camera, so photos carry Apple's depth (Off: the main camera,
            // unless Phased + Depth still needs the dual camera).
            updateDepthDevice()
        }
    }
    /// The camera delivers Apple depth now (Blur On on a phone with a depth camera).
    private(set) var bokehUsesDepth = false
    /// Which blur the last copy used ("apple depth · aperture …" or "custom").
    private(set) var lastBlurNote: String?

    var latchSteps: Bool = UserDefaults.standard.object(forKey: "guideLatch") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(latchSteps, forKey: "guideLatch")
            progress = GuideProgress()
        }
    }

    // Smoothed values for the step bars (live measurements jitter frame to frame).
    private(set) var barSizeRatio: Double?
    private(set) var barHeightError: Double?   // camera vs eyes minus target, + = camera too high
    private(set) var barTiltError: Double?     // pitch minus target, + = tilted down too much
    @ObservationIgnored private var smoothing: [String: Double] = [:]

    // MARK: Still-phone snapshot
    //
    // Vision boxes jitter and the motion sensor lags the camera while the phone moves, so the
    // camera-height and distance numbers jumped around. They are now measured only while the
    // phone is still: the median of the still frames is the reference ("snapshot"), and while
    // the phone moves that reference is frozen. Tilt and level stay live (sensor only).

    /// The phone has not turned more than `stillTolerance` degrees for `stillWindow` seconds.
    private(set) var isPhoneStill = false
    /// Still frames behind the current snapshot (debug).
    private(set) var snapshotFrames = 0
    @ObservationIgnored private var motionSamples: [(t: TimeInterval, pitch: Double, roll: Double)] = []
    @ObservationIgnored private var stillFrames: [(person: CGRect, face: CGRect?, pitch: Double, fov: Double?)] = []
    /// The snapshot keeps the field of view of its own frames: face, pitch and lens always come
    /// from the same moment (a frozen face with a newer zoom's FOV misread the phone height).
    @ObservationIgnored private var snapshot: (person: CGRect, face: CGRect?, pitch: Double, fov: Double?)?
    private static let stillWindow: TimeInterval = 0.3
    private static let stillTolerance = 1.0
    private static let snapshotSize = 8

    private func recordMotion(pitch: Double, roll: Double) {
        let now = ProcessInfo.processInfo.systemUptime
        motionSamples.append((now, pitch, roll))
        motionSamples.removeAll { now - $0.t > Self.stillWindow + 0.1 }
        let span = (motionSamples.last?.t ?? now) - (motionSamples.first?.t ?? now)
        let pitches = motionSamples.map { $0.pitch }, rolls = motionSamples.map { $0.roll }
        let steady = (pitches.max() ?? 0) - (pitches.min() ?? 0) < Self.stillTolerance
            && (rolls.max() ?? 0) - (rolls.min() ?? 0) < Self.stillTolerance
        let still = span >= Self.stillWindow && steady
        if still != isPhoneStill { isPhoneStill = still }
        if !still { stillFrames.removeAll() }      // moving: keep the last snapshot frozen
    }

    private func recordDetection() {
        guard let box = personBox else {
            stillFrames.removeAll()
            snapshot = nil
            snapshotFrames = 0
            return
        }
        // Only still frames of a settled zoom: frames from a moving zoom are not comparable.
        guard isPhoneStill, usesTeamGuide || zoomSettled(now: clockNow) else { return }
        stillFrames.append((box, face, pitch, verticalFOV))
        if stillFrames.count > Self.snapshotSize { stillFrames.removeFirst(stillFrames.count - Self.snapshotSize) }
        let faces = stillFrames.compactMap { $0.face }
        // A face only counts when it was found in at least half of the still frames.
        let medianFace: CGRect? = faces.count * 2 >= stillFrames.count ? Self.medianRect(faces) : nil
        snapshot = (person: Self.medianRect(stillFrames.map { $0.person }),
                    face: medianFace,
                    pitch: Self.median(stillFrames.map { $0.pitch }),
                    fov: stillFrames.last?.fov)
        snapshotFrames = stillFrames.count
    }

    private static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        return v.count % 2 == 0 ? (v[v.count / 2 - 1] + v[v.count / 2]) / 2 : v[v.count / 2]
    }

    private static func medianRect(_ rects: [CGRect]) -> CGRect {
        CGRect(x: median(rects.map { Double($0.minX) }), y: median(rects.map { Double($0.minY) }),
               width: median(rects.map { Double($0.width) }), height: median(rects.map { Double($0.height) }))
    }

    /// Mode C height step: where the eyes are now and where they must be in the frame for the
    /// preset's camera height at the CURRENT tilt (both live, so the rings follow the phone).
    /// The eyes sit on the target ring exactly when camera-vs-eyes equals the target.
    var heightRings: (eye: CGPoint, targetY: CGFloat)? {
        guard let face, let vfov = verticalFOV, vfov > 0,
              let target = evaluation.eyeElevationTarget else { return nil }
        let focal = 0.5 / tan(vfov * .pi / 360)
        let eye = CGPoint(x: face.midX, y: face.minY + face.height * GuideFlow.eyeFraction)
        // camera vs eyes = pitch − eyeAboveAxis  →  eyeAboveAxis = pitch − target
        let eyeAboveAxis = (pitch - target) * .pi / 180
        return (eye, CGFloat(0.5 - focal * tan(eyeAboveAxis)))
    }

    /// Mode E: the photographer holds the phone at the shown body height and taps Done.
    func confirmPhoneHeight() {
        progress.heightConfirmed = true
        updateInstruction()
    }

    /// Exponential smoothing; nil input resets the key.
    private func smoothed(_ key: String, _ value: Double?, weight: Double = 0.3) -> Double? {
        guard let value else { smoothing[key] = nil; return nil }
        let next = smoothing[key].map { $0 + weight * (value - $0) } ?? value
        smoothing[key] = next
        return next
    }

    /// The session the camera guides with, set by the view (`apply(sessionConfiguration:)`).
    /// The camera never picks a preference itself; the session's shot size is the picker's first
    /// selection. Nil = no preset (center target).
    private(set) var sessionConfiguration: PhotoSessionConfiguration?

    // The session's preset and what the AI learned from it (read from PreferencesViewModel).
    private(set) var presetName: String?
    private(set) var presetID: UUID?
    /// The session preset's reference photos (developer per-shot analysis screen).
    var presetPhotos: [PhotoItem] { presetID.flatMap { preferences.preference(id: $0)?.photos } ?? [] }
    /// The whole preset analysis (all shot sizes), for the shot size picker.
    private(set) var presetAnalysis: PresetAnalysis?
    /// The analysis guiding now: the picked shot size for the person's posture.
    private(set) var analysis: PresetAnalysis?
    private(set) var isAnalyzingPreset = false

    // MARK: Shot size picker (above the shutter) and posture

    /// Sitting / standing, smoothed over the last pose readings. Nil until read (or after the
    /// person was lost): treated like standing. Sitting can only be read with the legs in frame,
    /// so once read it is kept while the photographer frames tighter.
    private(set) var posture: BodyPosture?
    /// The photographer's pick among the standing shot sizes. Starts at the session's shot size;
    /// kept while the person sits (sitting always uses full body) and restored when they stand.
    private(set) var selectedShot: PresetAnalysis.ShotSize?
    @ObservationIgnored private var postureReadings: [BodyPosture] = []
    @ObservationIgnored private var personMissingSince: TimeInterval?
    /// Pose readings kept, and how many must agree to switch posture (first reading: fewer).
    private static let postureWindow = 6
    private static let postureSwitchVotes = 4
    private static let postureFirstVotes = 3

    /// What the picker offers now: sitting → full body only; standing → the preset's shot sizes.
    var shotOptions: [PresetAnalysis.ShotSize] {
        let options = presetAnalysis?.shotOptions(for: posture) ?? []
        // Phased does not support one-quarter yet (see `phasedLimitation`).
        return isPhased ? options.filter { $0 != .quarter } : options
    }

    /// The shot size guiding now: the pick when it is offered, else the preset's default, else the first option.
    var activeShot: PresetAnalysis.ShotSize? {
        let options = shotOptions
        if let selectedShot, options.contains(selectedShot) { return selectedShot }
        if let fallback = presetAnalysis?.defaultShot, options.contains(fallback) { return fallback }
        return options.first
    }

    /// A pick in the shot size picker: the guide starts over with that shot size.
    func selectShot(_ shot: PresetAnalysis.ShotSize) {
        guard shotOptions.contains(shot), shot != selectedShot else { return }
        selectedShot = shot
        if isReplay { restartReplay(reason: "shot changed") }
        updateInstruction()
    }

    /// One detection's pose reading. A posture switches once most recent readings agree; it is
    /// forgotten after the person has been gone for `GuideFlow.lostReset`.
    private func recordPosture(_ reading: BodyPosture?, personVisible: Bool) {
        let now = clockNow
        guard personVisible else {
            let since = personMissingSince ?? now
            personMissingSince = since
            if now - since >= GuideFlow.lostReset {
                postureReadings.removeAll()
                if posture != nil { posture = nil }
            }
            return
        }
        personMissingSince = nil
        guard let reading else { return }
        postureReadings.append(reading)
        if postureReadings.count > Self.postureWindow {
            postureReadings.removeFirst(postureReadings.count - Self.postureWindow)
        }
        guard reading != posture else { return }
        let votes = postureReadings.filter { $0 == reading }.count
        if votes >= (posture == nil ? Self.postureFirstVotes : Self.postureSwitchVotes) {
            posture = reading
        }
    }

    /// Phone pitch the camera aims for, or nil when there is no angle guidance.
    var targetPitch: Double? { Self.pitchTarget(for: analysis?.angle) }

    /// Values for the optional side-view pose guide (A / B, bottom right). Heights are the camera
    /// height against the subject's eyes, from the camera-vs-eyes angle and the estimated distance.
    var poseGuide: PoseGuideState {
        let e = evaluation
        func centimetres(_ angle: Double?) -> Double? {
            guard let angle, let d = e.distanceMeters, d > 0 else { return nil }
            return d * tan(angle * .pi / 180) * 100
        }
        // Face heights (version 17) → centimetres with a typical face; else the angle and distance.
        let faceCm = GuideFlow.faceHeightMeters * 100
        let heightOK = e.heightFaces.flatMap { now in
            e.heightFacesTarget.map { abs(now - $0) <= GuideFlow.heightFacesEnter }
        } ?? e.eyeElevation.flatMap { now in
            e.eyeElevationTarget.map { abs(now - $0) <= GuideFlow.heightEnter }
        } ?? true
        let tiltOK = pitchError.map { abs($0) <= GuideFlow.tiltEnter } ?? true
        return PoseGuideState(heightNow: e.heightFaces.map { $0 * faceCm } ?? centimetres(e.eyeElevation),
                              heightTarget: e.heightFacesTarget.map { $0 * faceCm } ?? centimetres(e.eyeElevationTarget),
                              tiltNow: -pitch, tiltTarget: targetPitch.map { -$0 },
                              distance: e.distanceMeters, heightOK: heightOK, tiltOK: tiltOK)
    }
    /// Phone pitch minus the target (+ = tilted further down than the target).
    var pitchError: Double? { targetPitch.map { pitch - $0 } }

    var isLevel: Bool { horizon == .level }

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var session: AVCaptureSession { cameraService.session }

    // MARK: Dependency (injected, like swiftshop's repositories)
    @ObservationIgnored private let cameraService: CameraServiceProtocol
    @ObservationIgnored private let motionService: MotionServiceProtocol
    @ObservationIgnored private let photoLibraryService: PhotoLibraryServiceProtocol
    @ObservationIgnored private let galleryStore: GalleryStoreProtocol
    @ObservationIgnored private let preferences: PreferencesViewModel

    init(cameraService: CameraServiceProtocol = CameraService(),
         motionService: MotionServiceProtocol = MotionService(),
         photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
         galleryStore: GalleryStoreProtocol? = nil,
         preferences: PreferencesViewModel? = nil,
         sessionConfiguration: PhotoSessionConfiguration? = nil,
         fixedSetup: (mode: GuideMode, aspect: CaptureAspect)? = nil){
        self.cameraService = cameraService
        self.motionService = motionService
        self.photoLibraryService = photoLibraryService
        self.galleryStore = galleryStore ?? GalleryStore()
        self.preferences = preferences ?? .shared
        self.sessionConfiguration = sessionConfiguration
        if let fixedSetup {   // testing mode: fixed, not saved
            savesSetup = false
            guideMode = fixedSetup.mode
            captureAspect = fixedSetup.aspect
            // appMode 1 = Phased · Auto crop (Reynard, 9 Nov; restored 13 Nov — cc5a19e switched it to No crop by
            // mistake). All tuning (distance aim, full-body band, left/right, roll by crop) is for Auto crop, and
            // the zoom stays 1×. No depth, Blur Off (the toggle is developer-only), no selector, no guide log.
            // Main modified and No crop stay in appMode 2.
            experiment = ExperimentSelection(guide: .phased, framing: .autoCrop)
        } else {              // appMode 2: the guide experiment (Main / Main modified run B + crop)
            experimentEnabled = true
            experiment = ExperimentSelection(guide: .saved(), framing: .saved())
            savesSetup = false
            guideMode = .heightFirstCrop
            savesSetup = true
        }
        self.cameraService.setOutlineEnabled(guideMode == .currentOldLook)
        self.cameraService.setHighResolution(guideMode.crops)
        // Opened on a Phased guide (appMode 1 always; appMode 2 when saved): set the camera up for it.
        if isPhased {
            experimentDidChange(from: ExperimentSelection(guide: .mainModified, framing: experiment.framing))
        }
    }

    // MARK: Intents (things the View asks for)

    /// A new session (or none): the guide starts over with its preset and effective shot size.
    func apply(sessionConfiguration configuration: PhotoSessionConfiguration?) {
        guard configuration != sessionConfiguration else { return }
        sessionConfiguration = configuration
        selectedShot = configuration?.effectiveShotSize
        progress = GuideProgress()
        adaptiveFOVReset()
        if isReplay { restartReplay(reason: "preset changed") }
        updateInstruction()
    }

    func startCamera() async {
        switch await cameraService.requestPermission() {
        case .granted: break
        case .denied:   state = .permissionDenied; return
        case .restricted: state = .restricted; return
        }

        do {
            try await cameraService.configure()
            await cameraService.start()
            state = .running
            if experimentEnabled, experiment.guide.usesDepth || bokehEnabled { updateDepthDevice() }
            if experimentEnabled, guideLog == nil, let log = GuideLogger() {
                guideLog = log
                var f = logBase()
                f["event"] = "session start"
                f.set("photoMegapixels", photoMegapixels)
                f["depth"] = .string(depthSupport.note)
                log.log("session", f)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func recheckPermission() async {
        guard state == .permissionDenied || state == .restricted else { return }
        await startCamera()
    }

    func observeTilt() async {
        for await tilt in motionService.tiltUpdates() {
            // Replay: the phone playing the video is not the camera that recorded it.
            if isReplay { continue }
            roll = tilt.roll
            pitch = tilt.pitch
            recordMotion(pitch: tilt.pitch, roll: tilt.roll)

            let next = HorizonState.next(roll: tilt.roll, pitch: tilt.pitch, current: horizon)
            if next != horizon {
                horizon = next
            }
            updateInstruction()
        }
        horizon = .hidden
    }

    // listens to person detection until the View's .task is cancelled
    func observePerson() async {
        for await detection in camera.personDetections() {
            // Replay: frames of an older run are stale; the clock is the frame's media time.
            if isReplay {
                guard let run = detection?.replayRun, run == replayRunNumber else { continue }
                if let t = detection?.mediaTime { replayClock = t; replayRecorder?.time(t) }
            } else if detection?.replayRun != nil {
                continue
            }
            // Strict lock (Phased) without a subject: only candidates, no person box.
            let subjectSeen = detection != nil && detection?.subjectLocked != false
            personBox = subjectSeen ? detection?.box : nil
            if detection?.outline != nil || personOutline != nil { personOutline = detection?.outline }
            face = subjectSeen ? detection?.face : nil
            let frameTime = clockNow
            if isPhased { recordPhasedDetection(detection, now: frameTime) }
            if isReplay { replayTrackSubject(subjectSeen, now: frameTime) }
            recordZoom(detection, now: frameTime)
            if subjectSeen, let box = detection?.box, zoomSettled(now: frameTime) {
                fovSamples.append((box, detection?.face))
                if fovSamples.count > Self.fovSampleCount { fovSamples.removeFirst(fovSamples.count - Self.fovSampleCount) }
            } else if !subjectSeen {
                fovSamples.removeAll()
            }
            if !subjectSeen {
                visibleJoints = nil
            } else if let joints = detection?.visibleJoints {
                visibleJoints = (joints, clockNow)
            }
            if let fov = detection?.verticalFOV { verticalFOV = fov }
            if let mp = detection?.photoMegapixels { photoMegapixels = mp }
            recordPosture(detection?.posture, personVisible: subjectSeen)
            recordDetection()
            updateInstruction()
            evaluateAdaptiveFOV()
        }
        personBox = nil
        personOutline = nil
        face = nil
        instruction = .findPerson
    }

    func observeEnvironment() async {
        for await signal in camera.environmentUpdates() {
            liveEnvironmentSignal = signal
            evaluateAdaptiveFOV()
        }
        liveEnvironmentSignal = nil
    }

    func observeZoom() async {
        for await zoom in camera.zoomUpdates() {
            let label = zoom.flatMap { value -> String? in
                guard value.isFinite, value > 0 else { return nil }
                return String(format: "%.1f×", value)
            }
            if label != currentZoomLabel {
                currentZoomLabel = label
            }
        }
        currentZoomLabel = nil
    }

    private func updateInstruction() {
        // Targets come from the session's preset and the shot size picked in the camera for the
        // person's posture (read live, so a finished analysis applies at once). A deleted preset
        // means no preset targets: another preset is never substituted here.
        let session = sessionConfiguration
        let preset = session.flatMap { preferences.preference(id: $0.preferenceID) }
        if preset?.id != presetID { presetID = preset?.id }
        if preset?.name != presetName { presetName = preset?.name }
        let whole = session == nil ? nil : preset?.analysis
        if whole != presetAnalysis { presetAnalysis = whole }
        var picked = activeShot.flatMap { whole?.guide(for: $0, posture: posture) }
        // Replay "distance locked" fixture (Main guides): reference size := baseline (synthetic).
        if isReplay, let fixture = replayMainFixture {
            let h = fixture.box.height / CGFloat(guideMode.distanceFactor)
            picked?.subjectBox = CGRect(x: fixture.box.minX, y: fixture.box.maxY - h, width: fixture.box.width, height: h)
            if let face = fixture.face { picked?.faceHeight = face / guideMode.distanceFactor }
        }
        if picked != analysis {
            // Another shot size or posture: the guide starts over with the new targets.
            if analysis != nil {
                progress = GuideProgress()
                adaptiveFOVReset()
            }
            analysis = picked
        }
        lighting.setLightLevel(preset?.analysis?.lightLevel)
        let analyzing = preset.map { preferences.isAnalyzing($0.id) } ?? false
        if analyzing != isAnalyzingPreset { isAnalyzingPreset = analyzing }

        let newTarget = analysis?.subjectBox.map { FramingTarget(rect: $0) } ?? .center
        if newTarget != target {
            target = newTarget
        }

        // Phased guides: their own engine (Core/Guide/Phased); Main's steps do not run.
        if isPhased {
            updatePhased()
            return
        }

        switch guideMode {
        case .current, .currentOldLook, .noAngle:
            let next = GuideInstruction.next(offset: personBox.map(target.offset(of:)),
                                             roll: roll,
                                             pitchError: guideMode == .noAngle ? nil : pitchError,
                                             current: instruction)
            if next != instruction {
                instruction = next
            }
            let plain = GuideEvaluation(instruction: next)
            if plain != evaluation { evaluation = plain }

        case .heightFirst, .heightFirstOld, .heightFirstCrop, .tiltFirst, .tiltFirstOld, .currentSteps, .currentStepsHeight, .fixedRules, .wideCrop:
            // Distance, camera height and position from the still-phone snapshot; tilt and level live.
            let snap = personBox == nil || !guideMode.usesSnapshot ? nil : snapshot
            let result: GuideEvaluation, nextProgress: GuideProgress
            if usesTeamGuide {
                // Main (team, a68494f): live field of view, no joints, no zoom turn-taking.
                let live = GuideLive(person: snap?.person ?? personBox, face: snap.map { $0.face } ?? face,
                                     verticalFOV: verticalFOV, roll: roll, pitch: pitch,
                                     photoMegapixels: photoMegapixels, measurePitch: snap?.pitch)
                (result, nextProgress) = TeamGuideFlow.evaluate(
                    mode: guideMode, live: live, analysis: analysis, target: target, targetPitch: targetPitch,
                    progress: progress, latch: latchSteps, now: clockNow)
            } else {
                let live = GuideLive(person: snap?.person ?? personBox, face: snap.map { $0.face } ?? face,
                                     verticalFOV: snap?.fov ?? verticalFOV, roll: roll, pitch: pitch,
                                     photoMegapixels: photoMegapixels, measurePitch: snap?.pitch,
                                     visibleJoints: visibleJoints.flatMap {
                                         clockNow - $0.at <= Self.jointsMaxAge ? $0.joints : nil
                                     },
                                     zoomWillHandleSize: zoomWillHandleSize)
                (result, nextProgress) = GuideFlow.evaluate(
                    mode: guideMode, live: live, analysis: analysis, target: target, targetPitch: targetPitch,
                    progress: progress, latch: latchSteps, now: clockNow)
            }
            let wasLatched = progress.latched.contains(.distance)
            progress = nextProgress
            let previousStep = evaluation.activeStep
            if result != evaluation { evaluation = result }

            // Size is smoothed in log space so "2x too close" and "2x too far" behave alike.
            barSizeRatio = smoothed("size", result.sizeRatio.map { log($0) }).map { exp($0) }
            let heightError: Double? = {
                // Face heights (version 17), scaled to degrees like the step's tolerance.
                if let now = result.heightFaces, let target = result.heightFacesTarget {
                    return (now - target) * GuideFlow.heightFacesScale
                }
                guard let now = result.eyeElevation, let target = result.eyeElevationTarget else { return nil }
                return now - target
            }()
            barHeightError = smoothed("height", heightError)
            barTiltError = smoothed("tilt", pitchError)
            // Replay: fixture, reopen marks, and steps that need sensors hidden (not evaluated).
            let shown = isReplay
                ? replayMainStep(result, previousStep: previousStep, wasLatched: wasLatched)
                : result.instruction
            if shown != instruction || result.activeStep != previousStep {
                logMainChange(result, previousStep: previousStep)
            }
            if shown != instruction {
                instruction = shown
            }
        }
    }

    // MARK: - Guide log (appMode 2)

    /// The session's log (appMode 2 only; nil in appMode 1).
    @ObservationIgnored private(set) var guideLog: GuideLogger?

    // MARK: GT recording (appMode 2, 12 Nov)
    /// On: the live analysis is logged twice a second and every shutter keeps the original photo and
    /// asks for ground truth (`GroundTruthEntry`). Off by default.
    var gtRecording = false {
        didSet {
            guard gtRecording != oldValue, let guideLog else { return }
            var f = logBase()
            f["event"] = .string(gtRecording ? "gt on" : "gt off")
            guideLog.log("gt", f)
        }
    }
    /// The form waiting for the photographer after a GT shutter.
    var gtPending: GroundTruthEntry?
    @ObservationIgnored private var gtLastTrack: TimeInterval = -1
    var gtExportFiles: [URL] { guideLog?.exportFiles ?? [] }

    func saveGroundTruth(_ entry: GroundTruthEntry) {
        gtPending = nil
        guard let guideLog else { return }
        guideLog.attachJSON(entry, named: entry.id + ".json")
        var f = logBase()
        f["event"] = "ground truth"
        f["gtID"] = .string(entry.id)
        f["skipped"] = .bool(entry.skipped)
        f.set("cameraVsEyesCm", entry.cameraVsEyesCm)
        f.set("heightLevel", entry.heightLevel)
        f.set("posture", entry.posture)
        f.set("facing", entry.facing)
        f.set("shot", entry.shot)
        guideLog.log("gt", f)
    }

    /// Common fields: app mode, guide, framing (Phased only), zoom.
    private func logBase(_ selection: ExperimentSelection? = nil) -> LogFields {
        let selection = selection ?? experiment
        var f = LogFields()
        f["appMode"] = 2
        f["guide"] = .string(selection.guide.rawValue)
        f.set("framing", selection.framingLabel)
        f.set("zoom", camera.currentZoom)
        f.set("preset", presetName)
        f.set("shot", activeShot?.rawValue)
        f.set("posture", posture.map { String(describing: $0) })
        if isReplay {
            f["source"] = "replay"
            f.set("mediaTime", replayClock)
            f["run"] = .int(replayRunNumber)
            f["scenario"] = .string(replayScenario.rawValue)
            f["sensors"] = "motion missing · fov missing · depth missing · zoom fixed 1 (not applied)"
            if replaySeeded { f["fixture"] = .string(ReplayScenario.fixtureID) }
        } else {
            f["source"] = "live"
        }
        return f
    }

    /// Main / Main modified: the instruction or the active step changed, and why.
    private func logMainChange(_ result: GuideEvaluation, previousStep: GuideStep?) {
        guard let guideLog else { return }
        var f = logBase()
        f["instruction"] = .string(String(describing: result.instruction))
        f.set("previousInstruction", String(describing: instruction))
        f.set("step", result.activeStep?.rawValue)
        f.set("previousStep", previousStep?.rawValue)
        f.set("distanceSource", result.distanceSource)
        f.set("sizeRatio", result.sizeRatio)
        f.set("heightFaces", result.heightFaces)
        f.set("heightFacesTarget", result.heightFacesTarget)
        f.set("eyeElevation", result.eyeElevation)
        f.set("eyeElevationTarget", result.eyeElevationTarget)
        f.set("pitch", pitch)
        f.set("pitchTarget", targetPitch)
        f.set("cutGuard", result.cutGuard)
        f.set("heightCapped", result.heightCapped)
        f["latched"] = .string(result.latched.map(\.rawValue).sorted().joined(separator: ","))
        guideLog.log("guide", f)
    }

    /// Phone pitch the preset asks for (`DeviceTilt` convention), or nil for no angle guidance.
    /// Not analysed yet or no angle readable: PRD fixed rule, phone straight (0 degrees).
    private static func pitchTarget(for angle: PresetAnalysis.AngleTarget?) -> Double? {
        switch angle {
        case .match(_, let pitchDown): return pitchDown
        case .fixedRule, nil:          return 0
        case .noGuidance:              return nil
        }
    }

    // MARK: - Adaptive FOV

    private func adaptiveFOVReset() {
        zoomSizeChangePending = false
        cutFloorZoom = nil
        adaptiveFOVTargetZoom = nil
        adaptiveFOVLastAppliedZoom = nil
        adaptiveFOVLastChangeTime = nil
        adaptiveFOVHoldSince = nil
        adaptiveFOVWasHold = false
        personLoss = PersonLossZoomReset()
        adaptiveFOVStatusText = nil
        adaptiveFOVStatusTask?.cancel()
        adaptiveFOVStatusTask = nil
    }

    private func adaptiveFOVShowStatus(_ text: String) {
        if adaptiveFOVStatusText != text {
            adaptiveFOVStatusText = text
        }
    }

    private func adaptiveFOVHideStatus(after delay: TimeInterval = 1.5) {
        adaptiveFOVStatusTask?.cancel()
        adaptiveFOVStatusTask = nil
        guard delay > 0 else {
            adaptiveFOVStatusText = nil
            return
        }
        adaptiveFOVStatusTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            // Only clear if no new status was set while waiting.
            if adaptiveFOVStatusTask?.isCancelled == false {
                adaptiveFOVStatusText = nil
            }
        }
    }

    private func adaptiveFOVMayAct() -> Bool {
        switch guideMode {
        case .current, .currentOldLook, .noAngle:
            switch instruction {
            case .moveCloser, .moveFarther, .holdStill:
                return true
            default:
                return false
            }
        default:
            if usesTeamGuide {   // Main (team, a68494f)
                if let activeStep = evaluation.activeStep { return activeStep == .distance }
                return isPhoneStill
            }
            // Zoom only while the distance step is open. Once it is done the zoom is locked (it
            // reopens only when the distance step breaks): a zoom after "ready" moved the framing
            // just as the photographer was about to shoot.
            return evaluation.activeStep == .distance
        }
    }

    private func adaptiveFOVApplyHysteresis(_ decision: AdaptiveFOV.Decision) -> AdaptiveFOV.Decision {
        let now = clockNow
        switch decision {
        case .hold:
            adaptiveFOVWasHold = true
            adaptiveFOVHoldSince = now
            return decision
        case .narrow, .widen:
            guard adaptiveFOVWasHold, let holdSince = adaptiveFOVHoldSince,
                  let currentZoom = camera.currentZoom else {
                adaptiveFOVWasHold = false
                adaptiveFOVHoldSince = nil
                return decision
            }
            let targetZoom: Double
            if case let .narrow(tz, _) = decision { targetZoom = tz }
            else if case let .widen(tz, _) = decision { targetZoom = tz }
            else { return decision }
            let requiredDelta = Self.adaptiveFOVHysteresisDeadband * currentZoom
            if abs(targetZoom - currentZoom) < requiredDelta {
                return .hold(reason: "hysteresis")
            }
            adaptiveFOVWasHold = false
            adaptiveFOVHoldSince = nil
            return decision
        }
    }

    private func adaptiveFOVClampRate(_ targetZoom: Double, now: TimeInterval) -> Double {
        guard let lastChangeTime = adaptiveFOVLastChangeTime,
              let lastApplied = adaptiveFOVLastAppliedZoom else {
            return targetZoom
        }
        let elapsed = now - lastChangeTime
        let maxDelta = Self.adaptiveFOVMaxRatePerSecond * elapsed
        let delta = targetZoom - lastApplied
        if abs(delta) <= maxDelta {
            return targetZoom
        } else {
            return lastApplied + (delta > 0 ? maxDelta : -maxDelta)
        }
    }

    private func evaluateAdaptiveFOV() {
        // Phased guides set the zoom themselves (1× / 2×, fixed per phase).
        if isPhased { return }
        if usesTeamGuide { evaluateAdaptiveFOVTeam(); return }
        let now = clockNow

        guard !adaptiveFOVZoomInFlight else { return }

        // Nobody in frame: no adaptive decision; keep the zoom for the grace period, then
        // return to 1.0x. A person (again): the existing adaptive zoom below decides.
        if handlePersonLoss(now: now) { return }

        guard let currentZoom = camera.currentZoom,
              let minZoom = camera.minAvailableZoom,
              let maxZoom = camera.maxAvailableZoom,
              currentZoom > 0, minZoom > 0, maxZoom >= minZoom,
              minZoom <= AdaptiveFOV.maximumAutomaticZoom,
              let person = personBox,
              target.rect.height > 0 else {
            zoomSizeChangePending = false
            adaptiveFOVHideStatus(after: 0)
            return
        }

        guard adaptiveFOVMayAct() else {
            zoomSizeChangePending = false
            adaptiveFOVHideStatus(after: 0.5)
            return
        }

        // Judge only a settled zoom, from the median of a few frames (the box wobbles).
        guard zoomSettled(now: now), fovSamples.count >= Self.fovMinSamples else { return }
        let medianPerson = Self.medianRect(fovSamples.map { $0.person })
        let faces = fovSamples.compactMap { $0.face }
        let medianFace = faces.count * 2 >= fovSamples.count ? Self.medianRect(faces) : nil
        _ = person

        let input = AdaptiveFOV.Input(
            personBox: medianPerson,
            face: medianFace,
            targetRect: target.rect,
            currentZoom: currentZoom,
            minZoom: minZoom,
            maxZoom: maxZoom,
            framing: analysis?.framing,
            targetFaceHeight: analysis.map { $0.faceHeight } ?? nil,
            clippedTop: analysis?.clippedTop ?? false,
            clippedBottom: analysis?.clippedBottom ?? false,
            distanceFactor: guideMode.distanceFactor,
            environment: liveEnvironmentSignal,
            preserveEnvironmentContext: shouldPreserveEnvironmentContext,
            now: now,
            shotSize: analysis?.shotSize.flatMap(PresetAnalysis.ShotSize.init(rawValue:)),
            visibleJoints: visibleJoints.flatMap { now - $0.at <= Self.jointsMaxAge ? $0.joints : nil },
            cutFloorZoom: cutFloorZoom
        )
        var decision = AdaptiveFOV.evaluate(input)
        decision = adaptiveFOVApplyHysteresis(decision)

        let proposedTarget: Double
        switch decision {
        case .narrow(let tz, _):
            proposedTarget = tz
        case .widen(let tz, _):
            proposedTarget = tz
        case .hold:
            zoomSizeChangePending = false
            adaptiveFOVHideStatus(after: 1.5)
            return
        }
        if isReplay { replayZoomIntent(proposedTarget, now: now) }
        let effectiveMaxZoom = min(maxZoom, AdaptiveFOV.maximumAutomaticZoom)
        // One target per decision; the camera's zoom ramp sets the speed (stepping the target
        // by a rate limit every frame made the zoom move in visible little jumps).
        let rateLimitedTarget = proposedTarget
        let clampedTarget = max(minZoom, min(effectiveMaxZoom, rateLimitedTarget))

        if let lastApplied = adaptiveFOVLastAppliedZoom,
           abs(clampedTarget - lastApplied) < 0.01 {
            zoomSizeChangePending = false            // the zoom cannot get there: the guide asks
            adaptiveFOVHideStatus(after: 1.5)
            return
        }

        let directionText: String
        if abs(clampedTarget - currentZoom) < 0.02 {
            // At its limit (or already there): nothing for the zoom to do, the guide asks.
            zoomSizeChangePending = false
            adaptiveFOVHideStatus(after: 0)
            return
        } else if clampedTarget > currentZoom {
            directionText = "Zooming in…"
        } else if clampedTarget < currentZoom {
            directionText = "Zooming out…"
        } else {
            zoomSizeChangePending = false
            adaptiveFOVHideStatus(after: 0)
            return
        }
        zoomSizeChangePending = true
        if case .narrow(_, let reason) = decision, reason.hasPrefix(AdaptiveFOV.cutReasonPrefix) {
            cutFloorZoom = clampedTarget
        }
        adaptiveFOVShowStatus(directionText)

        adaptiveFOVZoomInFlight = true
        adaptiveFOVTargetZoom = clampedTarget
        let generation = experimentGeneration
        Task {
            let applied = await self.camera.applyZoom(clampedTarget)
            self.adaptiveFOVZoomInFlight = false
            guard generation == self.experimentGeneration else { return }   // guide changed meanwhile
            self.adaptiveFOVLastAppliedZoom = applied
            self.adaptiveFOVLastChangeTime = clockNow
            self.adaptiveFOVTargetZoom = nil
            // Keep the status visible briefly after the zoom settles so the user can
            // perceive the change, then fade it out.
            self.adaptiveFOVHideStatus(after: 1.2)
        }
    }

    // MARK: Main (team): automatic zoom exactly as in main @ a68494f (live box, rate-clamped steps).

    private func evaluateAdaptiveFOVTeam() {
        let now = clockNow

        guard !adaptiveFOVZoomInFlight else { return }

        if handlePersonLoss(now: now) { return }

        guard let currentZoom = camera.currentZoom,
              let minZoom = camera.minAvailableZoom,
              let maxZoom = camera.maxAvailableZoom,
              currentZoom > 0, minZoom > 0, maxZoom >= minZoom,
              minZoom <= TeamAdaptiveFOV.maximumAutomaticZoom,
              let person = personBox,
              target.rect.height > 0 else {
            adaptiveFOVHideStatus(after: 0)
            return
        }

        guard adaptiveFOVMayAct() else {
            adaptiveFOVHideStatus(after: 0.5)
            return
        }

        let input = AdaptiveFOV.Input(
            personBox: person,
            face: face,
            targetRect: target.rect,
            currentZoom: currentZoom,
            minZoom: minZoom,
            maxZoom: maxZoom,
            framing: analysis?.framing,
            targetFaceHeight: analysis.map { $0.faceHeight } ?? nil,
            clippedTop: analysis?.clippedTop ?? false,
            clippedBottom: analysis?.clippedBottom ?? false,
            distanceFactor: guideMode.distanceFactor,
            environment: liveEnvironmentSignal,
            preserveEnvironmentContext: shouldPreserveEnvironmentContext,
            now: now
        )
        var decision = TeamAdaptiveFOV.evaluate(input)
        decision = adaptiveFOVApplyHysteresis(decision)

        let proposedTarget: Double
        switch decision {
        case .narrow(let tz, _):
            proposedTarget = tz
        case .widen(let tz, _):
            proposedTarget = tz
        case .hold:
            adaptiveFOVHideStatus(after: 1.5)
            return
        }
        if isReplay { replayZoomIntent(proposedTarget, now: now) }
        let effectiveMaxZoom = min(maxZoom, TeamAdaptiveFOV.maximumAutomaticZoom)
        let rateLimitedTarget = adaptiveFOVClampRate(proposedTarget, now: now)
        let clampedTarget = max(minZoom, min(effectiveMaxZoom, rateLimitedTarget))

        if let lastApplied = adaptiveFOVLastAppliedZoom,
           abs(clampedTarget - lastApplied) < 0.01 {
            adaptiveFOVHideStatus(after: 1.5)
            return
        }

        let directionText: String
        if clampedTarget > currentZoom {
            directionText = "Zooming in…"
        } else if clampedTarget < currentZoom {
            directionText = "Zooming out…"
        } else {
            adaptiveFOVHideStatus(after: 0)
            return
        }
        adaptiveFOVShowStatus(directionText)

        adaptiveFOVZoomInFlight = true
        adaptiveFOVTargetZoom = clampedTarget
        let generation = experimentGeneration
        Task {
            let applied = await self.camera.applyZoom(clampedTarget)
            self.adaptiveFOVZoomInFlight = false
            guard generation == self.experimentGeneration else { return }   // guide changed meanwhile
            self.adaptiveFOVLastAppliedZoom = applied
            self.adaptiveFOVLastChangeTime = clockNow
            self.adaptiveFOVTargetZoom = nil
            self.adaptiveFOVHideStatus(after: 1.2)
        }
    }

    /// Returns true when nobody is detected (the adaptive zoom must not run). After the grace
    /// period the zoom steps back to the baseline at the adaptive zoom's rate (0.5x per second),
    /// through the same `applyZoom`; once there, no further zoom commands are sent.
    private func handlePersonLoss(now: TimeInterval) -> Bool {
        let visible = personBox != nil
        guard let currentZoom = camera.currentZoom,
              let minZoom = camera.minAvailableZoom,
              let maxZoom = camera.maxAvailableZoom, currentZoom > 0 else {
            return !visible
        }
        let baseline = max(minZoom, min(maxZoom, AdaptiveFOV.baselineZoom))
        switch personLoss.update(personVisible: visible, currentZoom: currentZoom, baseline: baseline,
                                 ratePerSecond: Self.adaptiveFOVMaxRatePerSecond, now: now) {
        case .personVisible:
            return false
        case .waiting, .atBaseline:
            adaptiveFOVHideStatus(after: 0)
            return true
        case .step(let zoom):
            cutFloorZoom = nil
            zoomSizeChangePending = false
            // No "Zooming out…" capsule: nobody is being framed; the zoom label shows the change.
            adaptiveFOVHideStatus(after: 0)
            adaptiveFOVWasHold = false
            adaptiveFOVHoldSince = nil
            adaptiveFOVZoomInFlight = true
            Task {
                let applied = await self.camera.applyZoom(zoom)
                self.adaptiveFOVLastAppliedZoom = applied
                self.adaptiveFOVLastChangeTime = clockNow
                self.adaptiveFOVZoomInFlight = false
            }
            return true
        }
    }

    private var shouldPreserveEnvironmentContext: Bool {
        guard let id = presetID,
              let environment = preferences.session(for: id)?.profile?.environment else { return false }
        let finding = environment.transferable.environmentProminence
        guard finding.validObservationCount >= 2,
              finding.strength >= .moderate,
              finding.dominantShare >= 0.6,
              let dominant = finding.dominant else { return false }
        return dominant != .subjectDominates
    }

    func stopCamera() async {
        lighting.reset()
        personLoss.pause()   // no frames while stopped (gallery): not a lost person
        await camera.stop()
    }

    /// Restarts the feed after `stopCamera()` (the session is already set up).
    func resumeCamera() async {
        guard state == .running else { return }
        personLoss.pause()
        await camera.start()
    }

    /// Seconds from the tap to the moment the last photo was taken (debug panel).
    @ObservationIgnored private var shutterSeconds = 0.0

    /// The photo was taken: flash, haptic and a free shutter (its file is still processing).
    private func shutterFired(after start: Date) {
        guard isCapturing else { return }
        isCapturing = false
        captureCount += 1
        shutterSeconds = Date().timeIntervalSince(start)
    }

    func takePhoto() async {
        guard state == .running, !isCapturing else { return }
        isCapturing = true

        // The guide, framing and state at the shutter: a later mode switch never changes them.
        let shot = captureContext()
        let photo: CapturedPhoto
        let shutterAt = Date()
        do {
            // Flash + free the shutter at the moment the photo is taken, not when the (48 MP)
            // file is ready: with zero shutter lag that moment is the tap.
            photo = try await camera.capturePhoto(onShutter: { [weak self] in
                Task { @MainActor in self?.shutterFired(after: shutterAt) }
            })
        } catch {
            isCapturing = false
            errorMessage = error.localizedDescription
            return
        }
        shutterFired(after: shutterAt)                    // no-op if the shutter callback came first
        let captureSeconds = Date().timeIntervalSince(shutterAt)
        lastShotTiming = String(format: "shutter %.2fs · file %.2fs · processing…", shutterSeconds, captureSeconds)

        // Guide rectangles and aspect overlays are live composition aids, not crop instructions.
        let capturedData = photo.data
        let presetAtShot = presetID
        Task { [weak self] in
            guard let self else { return }
            let saveStart = Date()
            var originalID: String?
            // Phased · Auto crop: only the crop is saved (Reynard, 9 Nov: no second photo). The full
            // photo is saved only when no crop was made (nothing measurable yet, or the export failed).
            var crop: (result: PhasedCrop.Result, assetID: String?)?
            if let wanted = shot.phasedCrop {
                crop = await self.savePhasedCrop(of: capturedData, crop: wanted.rect, roll: wanted.roll,
                                                 floor: wanted.floor, presetID: presetAtShot)
            }
            if crop?.assetID == nil {
                // Gallery thumbnail, made from the file while Photos is still saving it
                let thumbnail = Self.makeThumbnail(of: capturedData)
                do {
                    if let assetID = try await self.photoLibraryService.save(imageData: capturedData) {
                        await Self.storeThumbnail(thumbnail, for: assetID)   // before the grid shows it
                        self.galleryStore.addCaptured(assetID: assetID, presetID: presetAtShot)
                        originalID = assetID
                    }
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
            self.lastShotTiming = String(format: "shutter %.2fs · file %.2fs · save %.2fs",
                                         self.shutterSeconds, captureSeconds, Date().timeIntervalSince(saveStart))
            if self.bokehEnabled { await self.saveBokehCopy(of: capturedData, presetID: presetAtShot) }
            self.logCapture(shot, data: capturedData, originalID: originalID, crop: crop?.result,
                            seconds: Date().timeIntervalSince(shutterAt))
        }
    }

    /// Saves a second photo with the background blurred (half strength). No person found = no copy.
    private func saveBokehCopy(of data: Data, presetID presetAtShot: UUID?) async {
        let start = Date()
        // Blur matched to the references (preset analysis v18); nil target = fallback strength.
        let target = analysis?.backgroundBlur
        let result = await Task.detached(priority: postCapturePriority) {
            BokehProcessor.blurToTarget(imageData: data, target: target)
        }.value
        lastBlurNote = result.note
        guard let blurred = result.data else {
            lastShotTiming = (lastShotTiming ?? "") + " · " + result.note
            return
        }
        let thumbnail = Self.makeThumbnail(of: blurred)
        do {
            if let assetID = try await photoLibraryService.save(imageData: blurred) {
                await Self.storeThumbnail(thumbnail, for: assetID)
                galleryStore.addCaptured(assetID: assetID, presetID: presetAtShot)
            }
            lastShotTiming = (lastShotTiming ?? "") + String(format: " · blur %.1fs (", Date().timeIntervalSince(start)) + result.note + ")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
      

    /// Saves the reviewed photo: the enhanced version (the original if the enhance failed).
    func saveReview() async {
        guard let review, !review.isEnhancing, !isSavingReview else { return }
        isSavingReview = true
        defer { isSavingReview = false }

        let original = review.photo.data
        let enhanced = review.enhanced
        let data = await Task.detached(priority: .userInitiated) {
            enhanced.flatMap { CapturedPhotoEnhancing.file(for: $0, metadataFrom: original) } ?? original
        }.value

        let thumbnail = Self.makeThumbnail(of: data)
        do {
            if let assetID = try await photoLibraryService.save(imageData: data) {
                await Self.storeThumbnail(thumbnail, for: assetID)
                galleryStore.addCaptured(assetID: assetID, presetID: presetID)
            }
            if self.review?.id == review.id { self.review = nil }
        } catch {
            self.review?.saveError = error.localizedDescription
        }
    }

    /// Starts building the gallery thumbnail from the photo file (background), so the gallery
    /// shows the photo instantly and sharp without asking Photos (slow for 48 MP files).
    private nonisolated static func makeThumbnail(of data: Data) -> Task<Data?, Never> {
        Task.detached(priority: .userInitiated) { ThumbnailCache.encodedThumbnail(from: data) }
    }

    private nonisolated static func storeThumbnail(_ thumbnail: Task<Data?, Never>, for assetID: String) async {
        await Task.detached(priority: .userInitiated) {
            if let encoded = await thumbnail.value {
                ThumbnailCache.shared.store(encoded: encoded, for: assetID)
            }
        }.value
    }

    /// Discards the reviewed photo and returns to the viewfinder.
    func retake() {
        enhanceTask?.cancel()
        enhanceTask = nil
        review = nil
    }
}

// MARK: - Phased guide (appMode 2 experiment)
//
// The engine (Core/Guide/Phased) decides; this glue feeds it the locked subject, sensors, zoom and
// depth, applies its zoom, shows its one instruction, and logs every transition with the guide
// and framing. Spec: Docs/Experiments/PhaseGuide/Spec-v3.md.

extension CameraViewModel {

    /// Called on every guide / framing change (and at launch when a Phased guide was saved).
    func experimentDidChange(from old: ExperimentSelection) {
        let phasedNow = isPhased
        camera.setStrictSubjectLock(phasedNow)
        setDimming(false)
        selector.reset()
        phasedCandidates = []
        phasedSubject = nil
        phasedDetectionTime = nil
        phasedLockedBox = nil
        phasedSubjectLocked = false
        phasedLandmarks = nil
        phasedExtent = nil
        phasedZoomTarget = nil
        lockRequested = nil
        latestDepth = nil
        phased = PhasedOutput()
        phasedInstruction = nil
        selectionDimMask = nil
        phasedEngine = phasedNow ? makePhasedEngine() : nil
        // Auto crop shoots the largest size (it crops); No crop and depth shoot about 12 MP.
        camera.setHighResolution(phasedNow
            ? experiment.framing == .autoCrop && !experiment.guide.usesDepth
            : guideMode.crops)
        if old.guide.usesDepth != experiment.guide.usesDepth { updateDepthDevice() }
        // Every guide starts at 1× (Phased picks its own zoom in phase 0).
        Task { _ = await camera.applyZoom(AdaptiveFOV.baselineZoom) }
    }

    private func makePhasedEngine() -> PhasedEngine {
        let depth = experiment.guide.usesDepth
        let params = PhasedParameters.standard
        let floor = phasedCropFloor(params)
        // Replay: crop geometry against a SIMULATED 48 MP source (the video's own pixels say nothing
        // about the camera's photo); labelled in the log.
        let source = isReplay ? ReplayCameraService.simulatedSourceMegapixels : photoMegapixels
        let minScale = experiment.framing == .autoCrop
            ? PhasedMeasure.cropMinScale(sourceMP: source, floorMP: floor) : 1
        let plan: PhasedEngine.ZoomPlan = experiment.framing == .noCrop && !depth ? .oneOrTwo : .fixedOne
        phasedEngineSourceMP = source
        let engine = PhasedEngine(params: params, policy: experiment.framing, zoomPlan: plan, cropMinScale: minScale)
        if let guideLog {
            var f = logBase()
            f["event"] = "engine"
            f.set("sourceMP", source)
            if isReplay { f["sourceMPNote"] = "simulated for crop geometry (replay)" }
            f.set("cropFloorMP", floor)
            f.set("cropMinScale", minScale)
            f["zoomPlan"] = .string(plan.rawValue)
            let b = engine.band
            f["sizeBand"] = .string(String(format: "enter %.2f–%.2f exit %.2f–%.2f reopen %.2f–%.2f",
                                           b.enterLow, b.enterHigh, b.exitLow, b.exitHigh, b.reopenLow, b.reopenHigh))
            f["parameters"] = .string(params.logSummary)
            guideLog.log("phased", f)
        }
        return engine
    }

    /// Dual camera + live depth for Phased + Depth (and the dual camera for Blur On).
    func updateDepthDevice() {
        let wantsDepthCamera = bokehEnabled || experiment.guide.usesDepth
        let wantsLiveDepth = experiment.guide.usesDepth
        let generation = experimentGeneration
        Task {
            if !wantsLiveDepth { _ = await camera.setLiveDepth(false) }
            let on = await camera.setDepthCapture(wantsDepthCamera)
            bokehUsesDepth = bokehEnabled && on
            guard generation == experimentGeneration else { return }
            if wantsLiveDepth {
                let support = on ? await camera.setLiveDepth(true)
                                 : LiveDepthSupport(available: false, note: "dual camera not available")
                liveDepth = support
                if let guideLog {
                    var f = logBase()
                    f["event"] = "live depth"
                    f["depthAvailable"] = .bool(support.available)
                    f["depthStatus"] = .string(support.note)
                    guideLog.log("phased", f)
                }
                // The photo size changed (depth photos ≈ 12 MP): new crop floor, guide restarts.
                if isPhased { phasedEngine = makePhasedEngine() }
            } else {
                liveDepth = nil
            }
        }
    }

    func observeDepth() async {
        for await sample in camera.depthUpdates() {
            latestDepth = sample
        }
        latestDepth = nil
    }

    /// Called for every detection while a Phased guide runs.
    func recordPhasedDetection(_ detection: PersonDetection?, now: TimeInterval) {
        guard let d = detection else {
            phasedCandidates = []
            phasedSubjectLocked = false
            phasedSubject = nil
            if selectionDimMask != nil, !dimmingOn { selectionDimMask = nil }
            return
        }
        phasedCandidates = d.candidates
        phasedZooming = d.isZooming
        if dimmingOn, let mask = d.dimMask { selectionDimMask = mask }
        guard d.subjectLocked else {
            phasedSubjectLocked = false
            phasedSubject = nil
            phasedLandmarks = nil
            phasedExtent = nil
            return
        }
        if let marks = d.landmarks { phasedLandmarks = (marks, now) }
        if let extent = d.extent {
            phasedExtent = (extent, d.extentEdges, now)
            if isReplay { replayRecorder?.sawMask() }
        }
        phasedSubjectLocked = true
        phasedLockedBox = d.box
        lockRequested = nil
        // Pose and mask run every few detections: their last values count for half a second.
        let fresh: (TimeInterval) -> Bool = { now - $0 <= 0.5 }
        let extent = phasedExtent.flatMap { fresh($0.at) ? $0 : nil }
        phasedSubject = SubjectObservation(box: d.box, face: d.face,
                                           landmarks: phasedLandmarks.flatMap { fresh($0.at) ? $0.marks : nil },
                                           extent: extent?.box, touches: extent?.edges ?? [])
        phasedDetectionTime = now
    }

    /// One update of the Phased guide (every detection and every motion update).
    func updatePhased() {
        guard var engine = phasedEngine else { return }
        let now = clockNow
        // The crop floor depends on the real photo size, known after the first frames — and it
        // changes with the camera (Blur On switches to the 12 MP depth camera), in any phase.
        if !isReplay, let mp = photoMegapixels, phasedEngineSourceMP != mp {
            engine = makePhasedEngine()
        }
        var events: [PhasedEvent] = []
        var made = PhasedTarget.make(analysis: analysis, shot: activeShot, posture: posture)
        // Replay "distance locked" fixture: reference size := baseline (synthetic, after the seed).
        // It belongs to the target it was seeded on: another shot size or posture drops it (logged).
        if isReplay, let fixture = replayFixtureSpan {
            if let t = made.target, t.shot == fixture.shot, t.sitting == fixture.sitting {
                made.target?.span = fixture.span
            } else {
                replayFixtureSpan = nil
                events.append(PhasedEvent(kind: "fixture lost",
                                          detail: "target changed (shot / posture): the simulated lock no longer applies"))
            }
        }
        events += engine.setTarget(made.target, problem: made.reason)
        let selection = selector.update(candidates: phasedCandidates, locked: phasedSubjectLocked,
                                        lockedBox: phasedLockedBox, now: now)
        handleSelection(selection, engine: &engine, events: &events)

        let frame = PhasedFrame(time: now,
                                subject: phasedSubjectLocked ? phasedSubject : nil,
                                detectionTime: phasedDetectionTime,
                                pitch: isReplay ? nil : pitch, roll: isReplay ? nil : roll,
                                phoneStill: isReplay ? false : isPhoneStill,
                                verticalFOV: verticalFOV, zoom: lastFrameZoom,
                                zoomStable: zoomSettled(now: now) && !phasedZooming,
                                nativeTwoX: camera.nativeZoomFactors.contains { abs($0 - 2) < 0.05 },
                                depth: experiment.guide.usesDepth ? latestDepth : nil,
                                frameAspect: replayInfo?.aspect ?? 3.0 / 4.0)
        let (out, more) = engine.step(frame)
        events += more
        // Replay scenario "distance locked": seeded ONCE, then the production rules run alone.
        if isReplay, replayScenario == .distanceLocked, !replaySeeded, let span = engine.fixtureBaselineSpan(now: now) {
            replaySeeded = true
            if let t = made.target { replayFixtureSpan = (span, t.shot, t.sitting) }
            events += engine.seedDistanceFixture(referenceSpan: span, now: now, fixtureID: ReplayScenario.fixtureID)
        }
        if isReplay, out.cropWindow != nil { replayRecorder?.sawCrop() }
        phasedEngine = engine
        if let zoom = out.zoomRequest { requestPhasedZoom(zoom, now: now) }

        let final: PhasedInstruction? = selection.instruction ?? (phasedSubjectLocked ? out.instruction : nil)
        if out != phased { phased = out }
        // GT recording: the live analysis twice a second (not only when the instruction changes).
        if gtRecording, let guideLog, clockNow - gtLastTrack >= 0.5 {
            gtLastTrack = clockNow
            var f = phasedFields(out)
            f["event"] = "track"
            f["instruction"] = .string(final?.rawValue ?? "none")
            guideLog.log("track", f)
        }
        if final != phasedInstruction {
            logPhasedInstruction(final, out)
            phasedInstruction = final
        }
        for event in events {
            logPhasedEvent(event, out)
            if event.kind == "phase" { flashPhaseDone(event.detail) }
        }
    }

    /// Green confirmation when a phase is finished (not when the guide moves back).
    private func flashPhaseDone(_ detail: String) {
        let names: [(String, String)] = [("distance →", "Distance"), ("vantage →", "Phone height"), ("tilt →", "Tilt")]
        guard let name = names.first(where: { detail.hasPrefix($0.0) })?.1 else { return }
        phasedFlashID += 1
        let id = phasedFlashID
        phasedFlash = name + " ✓"
        Task {
            try? await Task.sleep(for: .seconds(1.0))
            if self.phasedFlashID == id { self.phasedFlash = nil }
        }
    }

    private func handleSelection(_ s: PhasedSubjectPicker.Output, engine: inout PhasedEngine, events: inout [PhasedEvent]) {
        if case .lock(let box) = s.action, lockRequested != box {
            lockRequested = box
            camera.lockSubject(to: box)
            events.append(PhasedEvent(kind: "subject", detail: String(format: "lock at x%.2f y%.2f h%.2f",
                                                                     box.midX, box.midY, box.height)))
        }
        if s.newSubject { events += engine.subjectChanged() }
        setDimming(s.dims)
    }

    private func setDimming(_ on: Bool) {
        guard on != dimmingOn else { return }
        dimmingOn = on
        camera.setSelectionDimming(on)
        if !on { selectionDimMask = nil }
    }

    /// A tap on the preview while choosing (point in frame units, origin top-left).
    func tapPreview(at point: CGPoint) {
        guard isPhased, phasedInstruction == .tapPerson, var engine = phasedEngine else { return }
        var events: [PhasedEvent] = []
        let s = selector.tap(point, candidates: phasedCandidates)
        handleSelection(s, engine: &engine, events: &events)
        setDimming(false)
        phasedEngine = engine
        for event in events { logPhasedEvent(event, phased) }
    }

    /// Phased zoom: one request per target (the ramp then runs on its own).
    private func requestPhasedZoom(_ zoom: Double, now: TimeInterval) {
        guard let current = camera.currentZoom, abs(current - zoom) > 0.02, !phasedZooming else { return }
        if let last = phasedZoomTarget, abs(last.zoom - zoom) < 0.01, now - last.at < 1.5 { return }
        phasedZoomTarget = (zoom, now)
        Task { _ = await camera.applyZoom(zoom) }
    }

    /// Instruction animation for the motion overlay (height = translation, tilt = rotation).
    var phasedMotion: GuideInstruction { phasedInstruction?.motion ?? .findPerson }
    /// Pitch error for the tilt animation's swing (only when the tilt follows the reference pitch).
    var phasedPitchError: Double? { phased.tiltSource == "pitch" ? phased.tiltError : nil }

    /// Shown above the shot sizes in Phased when the preset has one-quarter photos.
    var phasedShotNote: String? {
        guard isPhased, presetAnalysis?.availableShots.contains(.quarter) == true else { return nil }
        return "1/4 isn't available in Phased yet"
    }

    var phasedDebugLines: [String] {
        let o = phased
        var lines = ["Phase \(o.phase.number) · \(o.phase.rawValue)" + (o.ready ? " · ready" : "")
                     + " · \(phasedInstruction?.rawValue ?? "no instruction")"]
        lines.append("Why: " + o.reason)
        if let r = o.sizeRatio { lines.append(String(format: "Size r %.2f (%@)", r, o.sizeSource)) }
        if let e = o.vantageError { lines.append(String(format: "Phone height %+.2f %@ · %@", e, o.vantageUnit, o.vantageSource)) }
        if let t = o.tiltError { lines.append(String(format: "Tilt %+.2f (%@)", t, o.tiltSource)) }
        if let c = o.cropWindow {
            lines.append(String(format: "Crop %.0f%% · x%.2f y%.2f · roll %+.1f°", c.height * 100, c.minX, c.minY, o.cropRoll))
        }
        if let l = o.limitation { lines.append("Limitation: " + l) }
        for missing in o.notEvaluated { lines.append("Not evaluated: " + missing) }
        if isReplay { lines.append(String(format: "Replay run %d · t %.2f s · %@", replayRunNumber, replayClock ?? 0, replayScenario.title)) }
        lines.append("Subject " + (phasedSubjectLocked ? "locked" : "none") + " · people \(phasedCandidates.count)"
                     + " · mask edges " + (phasedSubject?.touches.label ?? "—"))
        if experiment.guide.usesDepth {
            var line = "Depth: " + (liveDepth?.note ?? "starting")
            if let d = latestDepth {
                line += String(format: " · %.2f %@ · valid %.0f%%", d.value, d.absolute ? "m" : "rel", d.validFraction * 100)
            }
            lines.append(line)
        }
        return lines
    }

    // MARK: Log

    private func phasedFields(_ out: PhasedOutput) -> LogFields {
        var f = logBase()
        f["phase"] = .string(out.phase.rawValue)
        f.set("reason", out.reason)
        f.set("sizeRatio", out.sizeRatio)
        f.set("sizeSource", out.sizeSource)
        f.set("vantageError", out.vantageError)
        f["vantageUnit"] = .string(out.vantageUnit)
        f["vantageSource"] = .string(out.vantageSource)
        f.set("tiltError", out.tiltError)
        f.set("tiltSource", out.tiltSource)
        f.set("horizontalError", out.horizontalError)
        f.set("pitch", pitch)
        f.set("roll", roll)
        f["ready"] = .bool(out.ready)
        f.set("limitation", out.limitation)
        f["subjectLocked"] = .bool(phasedSubjectLocked)
        f.set("maskEdges", phasedSubject?.touches.label)
        // GT recording (12 Nov): the raw values behind the decisions, so the main analysis and the
        // measured truth can be compared with what the guide saw (only while recording).
        if gtRecording {
            func rect(_ r: CGRect?) -> LogValue? {
                r.map { .string(String(format: "%.4f,%.4f,%.4f,%.4f", $0.minX, $0.minY, $0.width, $0.height)) }
            }
            f["subjectBox"] = rect(phasedSubject?.box)
            f["faceBox"] = rect(phasedSubject?.face)
            f["maskBox"] = rect(phasedSubject?.extent)
            f["captureCrop"] = rect(out.captureCrop)
            f.set("captureRoll", out.captureRoll)
            f.set("verticalFOV", verticalFOV)
            f.set("tiltNeed", out.tiltNeed)
            f.set("sizeEnterLow", out.sizeEnterLow)
            f.set("sizeEnterHigh", out.sizeEnterHigh)
            if let t = phasedEngine?.target {
                f["targetShot"] = .string(t.shot.rawValue)
                f.set("targetSpan", t.span)
                f.set("targetTop", t.top)
                f.set("targetMidX", t.midX)
                f.set("targetVantageFaces", t.vantageFaces)
                f.set("targetVantageDegrees", t.vantageDegrees)
                f.set("targetPitch", t.pitch)
                f["targetSitting"] = .bool(t.sitting)
            }
            if !out.notEvaluated.isEmpty { f["notEvaluated"] = .string(out.notEvaluated.joined(separator: " | ")) }
        }
        if let c = out.cropWindow {
            f["crop"] = .string(String(format: "%.3f,%.3f,%.3f,%.3f", c.minX, c.minY, c.width, c.height))
        }
        if experiment.guide.usesDepth {
            f.set("depthStatus", liveDepth?.note)
            f.set("depth", latestDepth?.value)
            f.set("depthValid", latestDepth?.validFraction)
            f.set("depthAbsolute", latestDepth?.absolute)
        }
        return f
    }

    private func logPhasedInstruction(_ new: PhasedInstruction?, _ out: PhasedOutput) {
        replayRecorder?.instruction(new?.rawValue ?? "none", at: clockNow)
        guard let guideLog else { return }
        var f = phasedFields(out)
        f["event"] = "instruction"
        f["instruction"] = .string(new?.rawValue ?? "none")
        f["previousInstruction"] = .string(phasedInstruction?.rawValue ?? "none")
        guideLog.log("phased", f)
    }

    private func logPhasedEvent(_ event: PhasedEvent, _ out: PhasedOutput) {
        replayRecorder?.mark(event.kind, event.detail, at: clockNow)
        guard let guideLog else { return }
        var f = phasedFields(out)
        f["event"] = .string(event.kind)
        f["detail"] = .string(event.detail)
        for (key, value) in event.values { f.set(key, value) }
        guideLog.log("phased", f)
    }

    // MARK: Capture

    /// What the guide looked like at the shutter (the log and the crop use this, never later state).
    struct CaptureContext {
        var selection: ExperimentSelection
        var fields: LogFields
        /// Phased · Auto crop with a crop valid at the shutter.
        var phasedCrop: (rect: CGRect, roll: Double, floor: Double)?
    }

    func captureContext() -> CaptureContext {
        var f = isPhased ? phasedFields(phased) : logBase()
        f.set("instruction", isPhased ? (phasedInstruction?.rawValue ?? "none") : String(describing: instruction))
        if !isPhased {
            f.set("step", evaluation.activeStep?.rawValue)
            f.set("ready", isReady)
        }
        f.set("photoMegapixelsMax", photoMegapixels)
        f.set("blur", bokehEnabled)
        var crop: (rect: CGRect, roll: Double, floor: Double)?
        // Auto crop: the final crop when ready; before that the crop valid right now (shaky hands
        // still get a framed photo). Nothing measurable yet = no crop.
        if isPhased, experiment.framing == .autoCrop,
           let window = phased.cropWindow ?? phased.captureCrop {
            let params = PhasedParameters.standard
            crop = (window, phased.cropWindow != nil ? phased.cropRoll : phased.captureRoll, phasedCropFloor(params))
            f["cropBasis"] = .string(phased.cropWindow != nil ? "ready" : "early (\(phased.phase.rawValue))")
        }
        return CaptureContext(selection: experiment, fields: f, phasedCrop: crop)
    }

    /// Crop floor: 12 MP, or 8 MP when the photo comes from the depth camera (Phased + Depth, or
    /// Blur On: both capture 12 MP, where a 12 MP floor left no room to crop — log 16:59).
    private func phasedCropFloor(_ params: PhasedParameters) -> Double {
        experiment.guide.usesDepth || bokehEnabled ? params.depthCropFloorMegapixels : params.cropFloorMegapixels
    }

    /// Post-shutter work below the live detection in appMode 2: Blur On renders took 28–48 s and
    /// starved the guide (no detections, no instruction) — log 16:59. appMode 1 keeps its priority.
    private var postCapturePriority: TaskPriority { experimentEnabled ? .utility : .userInitiated }

    /// Saves the Auto crop as THE photo (no full-frame copy). Asset ID nil = not saved (no crop
    /// made or the save failed): the caller then saves the full photo instead.
    func savePhasedCrop(of data: Data, crop: CGRect, roll: Double, floor: Double,
                        presetID presetAtShot: UUID?) async -> (result: PhasedCrop.Result, assetID: String?) {
        let result = await Task.detached(priority: postCapturePriority) {
            PhasedCrop.apply(imageData: data, crop: crop, rollDegrees: roll, floorMegapixels: floor)
        }.value
        guard let cropped = result.data else { return (result, nil) }
        let thumbnail = Self.makeThumbnail(of: cropped)
        do {
            if let assetID = try await photoLibraryService.save(imageData: cropped) {
                await Self.storeThumbnail(thumbnail, for: assetID)
                galleryStore.addCaptured(assetID: assetID, presetID: presetAtShot)
                var r = result
                r.note += " · saved " + assetID
                return (r, assetID)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return (result, nil)
    }

    func logCapture(_ shot: CaptureContext, data: Data, originalID: String?, crop: PhasedCrop.Result?, seconds: Double) {
        guard let guideLog, experimentEnabled else { return }
        var f = shot.fields
        f["guide"] = .string(shot.selection.guide.rawValue)
        f.set("framing", shot.selection.framingLabel)
        let size = crop?.sourceSize ?? Self.pixelSize(of: data)
        f["sourceSize"] = .string(String(format: "%.0f×%.0f", size.width, size.height))
        f.set("originalAsset", originalID)
        f["saved"] = .string(originalID == nil && crop?.data != nil ? "crop only" : "full photo")
        if let crop {
            f["cropNote"] = .string(crop.note)
            if let out = crop.outputSize { f["outputSize"] = .string(String(format: "%.0f×%.0f", out.width, out.height)) }
            if let a = crop.applied {
                f["cropApplied"] = .string(String(format: "%.3f,%.3f,%.3f,%.3f", a.minX, a.minY, a.width, a.height))
            }
            f.set("cropRollApplied", crop.rollDegrees)
        } else {
            f["outputSize"] = .string(String(format: "%.0f×%.0f", size.width, size.height))
            f["cropApplied"] = "none"
        }
        f.set("secondsToSaved", seconds)
        // GT recording: keep the original photo (the main analysis runs on it later) and ask for truth.
        if gtRecording {
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyyMMdd-HHmmss-SSS"
            stamp.locale = Locale(identifier: "en_US_POSIX")
            let id = "gt-" + stamp.string(from: Date())
            let ext = Self.isHEIC(data) ? "heic" : "jpg"
            guideLog.attach(data, named: id + "." + ext)
            f["gtID"] = .string(id)
            f["gtPhoto"] = .string(id + "." + ext)
            gtPending = GroundTruthEntry(id: id, shot: activeShot?.rawValue, guideShot: activeShot?.rawValue)
        }
        guideLog.capture(f)
    }

    nonisolated static func isHEIC(_ data: Data) -> Bool {
        guard data.count > 12 else { return false }
        let brand = String(decoding: data[8..<12], as: UTF8.self)
        return ["heic", "heix", "hevc", "mif1", "msf1"].contains(brand)
    }

    nonisolated static func pixelSize(of data: Data) -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Double,
              let h = props[kCGImagePropertyPixelHeight] as? Double else { return .zero }
        return CGSize(width: w, height: h)
    }
}

// MARK: - Replay video (appMode 2 testing)
//
// A video replaces the camera: `ReplayCameraService` feeds its frames to the same detector, guide
// and log code; zoom / capture go nowhere. Clock = media time; paused = no frames = no time.
// Spec: Docs/Experiments/Replay/Spec.md. Open-loop: the person in the video does not follow the guide.

extension CameraViewModel {

    /// Depth for the picker: never in Replay (a plain video carries no depth).
    var effectiveDepthSupport: LiveDepthSupport {
        isReplay ? LiveDepthSupport(available: false, note: "This video has no depth data") : depthSupport
    }

    /// Permanent label while replaying.
    var replayBadge: String { "Replay · RGB only" }
    var replayIsSimulation: Bool { isReplay && replayScenario == .distanceLocked }
    var replayRunID: String { "\(guideLog?.sessionName ?? "replay")-r\(replayRunNumber)" }

    /// Switches the source to Replay (a video is picked next). The live camera stops: it must not
    /// measure the scene of the video playing on screen.
    func enterReplay() async {
        guard experimentEnabled, !isReplay else { return }
        await cameraService.stop()
        isReplay = true
        replayMessage = "Pick a video (Files or Photos)."
        clearLiveSensors()
        if experiment.guide.usesDepth {
            experiment.guide = .phased          // depth cannot be replayed from a video
            replayMessage = "Phased + Depth is off in Replay: this video has no depth data."
        }
        sourceID += 1
        resetGuideState()
        if let guideLog {
            var f = logBase()
            f["event"] = "replay on"
            guideLog.log("replay", f)
        }
    }

    /// Back to the camera: replay state, fixture and simulated values are dropped.
    func exitReplay() async {
        guard isReplay else { return }
        cancelReplayBatch("stopped: back to live")
        finishReplayRun()
        replayService?.source.stop()
        replayService = nil
        isReplay = false
        replayInfo = nil
        replayImage = nil
        replayClock = nil
        replayPlaying = false
        replayEnded = false
        replayMaskNote = nil
        replayMessage = nil
        clearFixture()
        clearLiveSensors()
        sourceID += 1
        resetGuideState()
        if let guideLog {
            var f = logBase()
            f["event"] = "replay off"
            guideLog.log("replay", f)
        }
        await cameraService.start()
    }

    /// Opens a video (already copied into the app) and starts a paused run at its beginning.
    func loadReplayVideo(_ url: URL) async {
        guard isReplay else { return }
        do {
            let source = try await VideoReplaySource.open(url)
            cancelReplayBatch("stopped: new video")
            finishReplayRun()
            replayService?.source.stop()
            replayService = ReplayCameraService(source: source)
            replayInfo = source.info
            replayMessage = source.info.hasDepthTrack
                ? "The file has a depth track, but no synchronized recorder format exists yet: not used."
                : nil
            sourceID += 1
            restartReplay(reason: "video loaded")
        } catch {
            replayMessage = error.localizedDescription
        }
    }

    func replayPlayPause() {
        guard let service = replayService else { return }
        if replayPlaying {
            service.pause()
            replayPlaying = false
            replayRecorder?.mark("pause", "", at: clockNow)
        } else {
            if replayEnded { restartReplay(reason: "play again") }
            service.play()
            replayPlaying = true
            replayRecorder?.mark("play", "", at: clockNow)
        }
    }

    /// A new run from the start: everything the guide learned is dropped (cold start, same baseline).
    func restartReplay(reason: String, fromBatch: Bool = false) {
        guard isReplay, let service = replayService, let info = replayInfo else { return }
        if !fromBatch, replayBatch != nil { cancelReplayBatch("stopped: \(reason)") }
        finishReplayRun()
        replayRunNumber += 1
        replayClock = nil
        replayPlaying = false
        replayEnded = false
        replayTime = 0
        replayImage = nil
        replayExports = []
        clearFixture()
        resetGuideState()
        service.restart(run: replayRunNumber)
        let config: [String: String] = [
            "video": info.name, "sha256": info.sha256, "duration": String(format: "%.2f", info.duration),
            "size": String(format: "%.0fx%.0f", info.uprightSize.width, info.uprightSize.height),
            "trackSize": String(format: "%.0fx%.0f", info.trackSize.width, info.trackSize.height),
            "rotation": String(format: "%.0f", info.rotation), "mirrored": "\(info.mirrored)",
            "fps": String(format: "%.2f", info.nominalFrameRate),
            "extraTracks": info.extraTracks.joined(separator: " "),
            "guide": experiment.guide.rawValue, "framing": experiment.framingLabel ?? "",
            "preset": presetName ?? "", "shot": activeShot?.rawValue ?? "",
            "reason": reason, "analysisStride": "\(ReplayCameraService.analysisStride)",
            "sensors": "motion missing; fov missing; depth missing; zoom fixed 1 not applied"
                + (experiment.framing == .autoCrop && isPhased ? "; crop source simulated 48 MP" : ""),
            "parameters": PhasedParameters.standard.logSummary,
            "scenario": replayScenario.rawValue,
            "batch": replayBatch.map { "\($0.id) \($0.index + 1)/\($0.items.count)" } ?? "",
        ]
        replayRecorder = ReplayRunRecorder(runID: replayRunID, config: config)
        if let guideLog {
            var f = logBase()
            f["event"] = "run start"
            f["reason"] = .string(reason)
            for (k, v) in config { f[k] = .string(v) }
            guideLog.log("replay", f)
        }
    }

    /// Ends the run's record: writes its JSON and CSV row; the files become shareable.
    func finishReplayRun() {
        guard var recorder = replayRecorder, let service = replayService else { replayRecorder = nil; return }
        replayRecorder = nil
        recorder.finish(at: replayClock ?? 0)
        let stats = service.currentStats()
        // A run that never showed a frame (settings changed before play) is not a result.
        guard stats.shown > 0 else { return }
        let scenario = recorder.config["scenario"].flatMap(ReplayScenario.init(rawValue:)) ?? replayScenario
        let phased = recorder.config["guide"].flatMap(ExperimentGuide.init(rawValue:))?.isPhased ?? isPhased
        var urls = recorder.write(stats: stats, scenario: scenario, phased: phased,
                                  alsoAppendTo: replayBatch?.csvURL)
        if let log = guideLog?.fileURL { urls.append(log) }
        replayExports = urls
        replayBatch?.runIDs.append(recorder.runID)
        if let guideLog {
            var f = logBase()
            f["event"] = "run end"
            // The run's own settings (the current ones may already belong to the next run).
            for key in ["guide", "framing", "shot", "preset", "batch"] { f[key] = .string(recorder.config[key] ?? "") }
            f["run"] = .string(recorder.runID)
            f["shown"] = .int(stats.shown)
            f["analysed"] = .int(stats.analysed)
            f["droppedBusy"] = .int(stats.droppedBusy)
            f.set("lagMean", stats.lagMean)
            f.set("lagMax", stats.lagMax)
            f["reopens"] = .int(recorder.reopens)
            f["reversals"] = .int(recorder.reversals)
            guideLog.log("replay", f)
        }
    }

    /// "Save test frame": the current frame as JPEG in the replay results, with the run ID (never the
    /// photo library, never a camera capture).
    func saveTestFrame() {
        guard let frame = replayService?.lastFrame() else { replayMessage = "No frame yet."; return }
        do {
            let url = try ReplayLibrary.saveFrame(frame, runID: replayRunID)
            replayRecorder?.mark("test frame", url.lastPathComponent, at: frame.mediaTime)
            replayMessage = "Saved test frame " + url.lastPathComponent
        } catch {
            replayMessage = error.localizedDescription
        }
    }

    func observeReplayPreview() async {
        guard let service = replayService else { return }
        for await frame in service.previewFrames() {
            guard frame.run == replayRunNumber else { continue }
            replayImage = frame.image
            replayTime = frame.mediaTime
        }
    }

    func observeReplayEnd() async {
        guard let service = replayService else { return }
        for await end in service.endEvents() {
            guard end.run == replayRunNumber, isReplay else { continue }
            replayPlaying = false
            guard end.completed else {
                // Not a result: the video did not play to the end (e.g. the app went to the
                // background). The run is dropped and started again from 0:00.
                replayRecorder?.mark("interrupted", end.why, at: clockNow)
                if let guideLog {
                    var f = logBase()
                    f["event"] = "run interrupted"
                    f["detail"] = .string(end.why)
                    guideLog.log("replay", f)
                }
                replayRecorder = nil              // never written as a run
                if replayBatch != nil {
                    replayMessage = "Run interrupted (\(end.why)): repeating it."
                    runReplayBatchItem()
                } else {
                    replayMessage = "Playback interrupted (\(end.why)): run discarded, press play to start again."
                    restartReplay(reason: "interrupted")
                }
                continue
            }
            replayEnded = true
            replayRecorder?.mark("end", end.why, at: clockNow)
            finishReplayRun()
            if replayBatch != nil { advanceReplayBatch() }
        }
    }

    /// The app leaves the foreground: replay pauses (a background reader fails; Run all waits).
    func replayAppInactive() {
        guard isReplay, replayPlaying, let service = replayService else { return }
        service.pause()
        replayPlaying = false
        replayRecorder?.mark("pause", "app inactive", at: clockNow)
        replayMessage = replayBatch != nil ? "Run all paused (app inactive): press play to continue." : nil
    }

    // MARK: Run all (batch)

    /// Replays the video once per guide × framing × shot size (full, 3/4, half) for the scenarios
    /// given, one after another, each a cold start at 1×. Depth is skipped (no depth in a video).
    func startReplayBatch(scenarios: [ReplayScenario]) {
        guard isReplay, replayService != nil else { return }
        if replayBatch != nil { cancelReplayBatch("restarted") }
        let available = presetAnalysis?.shotOptions(for: nil) ?? []
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let plan = ReplayBatchPlan.make(id: stamp.string(from: Date()), scenarios: scenarios, available: available,
                                        restore: experiment, restoreShot: selectedShot, restoreScenario: replayScenario)
        guard !plan.items.isEmpty else {
            replayMessage = "Run all: no shot size to test (full / 3/4 / half missing in the preset)."
            return
        }
        finishReplayRun()              // a manual run before the batch is not part of it
        replayRecorder = nil
        replayBatch = plan
        if let guideLog {
            var f = logBase()
            f["event"] = "batch start"
            f["batch"] = .string(plan.id)
            f["runs"] = .int(plan.items.count)
            f["skipped"] = .string(plan.skipped.joined(separator: "; "))
            guideLog.log("replay", f)
        }
        runReplayBatchItem()
    }

    func cancelReplayBatch(_ why: String) {
        guard let plan = replayBatch else { return }
        replayBatch = nil
        replayBatchStatus = nil
        replayMessage = "Run all \(why) after \(plan.runIDs.count) of \(plan.items.count) runs."
        if let guideLog {
            var f = logBase()
            f["event"] = "batch cancelled"
            f["batch"] = .string(plan.id)
            f["detail"] = .string(why)
            guideLog.log("replay", f)
        }
    }

    private func runReplayBatchItem() {
        guard let plan = replayBatch, let item = plan.current, let service = replayService else { return }
        replayApplyingBatch = true
        experiment = ExperimentSelection(guide: item.guide, framing: item.framing)
        selectedShot = item.shot
        replayScenario = item.scenario
        replayApplyingBatch = false
        let step = "\(plan.index + 1)/\(plan.items.count)"
        replayBatchStatus = "Run all \(step) · \(item.label)"
        restartReplay(reason: "run all \(step): \(item.label)", fromBatch: true)
        service.play()
        replayPlaying = true
        replayRecorder?.mark("play", "run all", at: clockNow)
    }

    private func advanceReplayBatch() {
        guard var plan = replayBatch else { return }
        plan.index += 1
        replayBatch = plan
        guard plan.current != nil else { finishReplayBatch(); return }
        let run = replayRunNumber
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            // Still the same batch, nothing touched meanwhile.
            guard self.replayBatch?.id == plan.id, self.replayRunNumber == run else { return }
            self.runReplayBatchItem()
        }
    }

    private func finishReplayBatch() {
        guard let plan = replayBatch else { return }
        replayBatch = nil
        replayBatchStatus = nil
        // Put the operator's settings back (no extra run for it), then a fresh paused run.
        replayApplyingBatch = true
        experiment = plan.restoreSelection
        selectedShot = plan.restoreShot
        replayScenario = plan.restoreScenario
        replayApplyingBatch = false
        restartReplay(reason: "run all finished", fromBatch: true)
        let jsons = plan.runIDs.map { ReplayLibrary.results.appending(path: "replay-\($0).json") }
        replayExports = [plan.csvURL] + jsons + [ReplayLibrary.summaryCSV] + (guideLog.map { [$0.fileURL] } ?? [])
        replayMessage = "Run all done: \(plan.runIDs.count) runs. Skipped: " + plan.skipped.joined(separator: "; ")
        if let guideLog {
            var f = logBase()
            f["event"] = "batch end"
            f["batch"] = .string(plan.id)
            f["runs"] = .int(plan.runIDs.count)
            guideLog.log("replay", f)
        }
    }

    // MARK: Internals

    /// Phone sensors are not the recording camera's: drop their values (missing, not 0-as-truth).
    private func clearLiveSensors() {
        pitch = 0                 // placeholder only for Main (its later steps are hidden in Replay)
        roll = 0
        isPhoneStill = false
        motionSamples.removeAll()
        horizon = .hidden
        verticalFOV = nil
        photoMegapixels = nil
        latestDepth = nil
    }

    private func clearFixture() {
        replaySeeded = false
        replayBaseline = []
        replayBaselineSince = nil
        replayFixtureSpan = nil
        replayMainFixture = nil
        replaySubjectSeen = nil
        replayEverLocked = false
    }

    /// Cold start of every guide: steps, phases, subject lock, zoom state, smoothing, snapshot.
    private func resetGuideState() {
        experimentGeneration += 1
        progress = GuideProgress()
        evaluation = GuideEvaluation()
        instruction = .findPerson
        adaptiveFOVReset()
        smoothing.removeAll()
        stillFrames.removeAll()
        snapshot = nil
        snapshotFrames = 0
        fovSamples.removeAll()
        lastFrameZoom = nil
        zoomQuietSince = nil
        visibleJoints = nil
        postureReadings.removeAll()
        posture = nil
        personMissingSince = nil
        personBox = nil
        face = nil
        replayMaskNote = nil
        experimentDidChange(from: experiment)
        updateInstruction()
    }

    /// Lock / loss / reacquisition marks by media time.
    func replayTrackSubject(_ seen: Bool, now: TimeInterval) {
        guard seen != replaySubjectSeen else { return }
        let first = replaySubjectSeen == nil
        replaySubjectSeen = seen
        if seen {
            replayRecorder?.mark(replayEverLocked ? "reacquire" : "lock", "", at: now)
            replayEverLocked = true
        } else if !first {
            replayRecorder?.mark("loss", "", at: now)
        }
    }

    /// Main / Main modified in Replay: the "distance locked" fixture (baseline 1 s of media time,
    /// then seeded once as a latched distance step), reopen marks, and the instruction to show: steps
    /// after distance (and "ready") need motion / field of view and are hidden as not evaluated.
    func replayMainStep(_ result: GuideEvaluation, previousStep: GuideStep?, wasLatched: Bool) -> GuideInstruction {
        let now = clockNow
        if wasLatched, !result.latched.contains(.distance), replaySeeded || !progress.latched.isEmpty {
            replayRecorder?.mark("reopen", "distance released by \(usesTeamGuide ? "TeamGuideFlow" : "GuideFlow")", at: now)
        }
        if result.activeStep != previousStep {
            replayRecorder?.mark("step", "\(previousStep?.rawValue ?? "none") → \(result.activeStep?.rawValue ?? "none")", at: now)
        }
        if replayScenario == .distanceLocked, !replaySeeded {
            if replayMainFixture != nil {
                // The fixture target is in place (applied at the top of this update): seed once.
                progress.latched.insert(.distance)
                progress.okSince[.distance] = now
                replaySeeded = true
                replayRecorder?.mark("fixture", "\(ReplayScenario.fixtureID): distance step latched (simulated state)", at: now)
                if let guideLog {
                    var f = logBase()
                    f["event"] = "fixture seeded"
                    guideLog.log("replay", f)
                }
            } else if let box = personBox {
                if replayBaselineSince == nil { replayBaselineSince = now }
                replayBaseline.append((box, face.map { Double($0.height) }))
                if let since = replayBaselineSince, now - since >= 1.0, replayBaseline.count >= 6 {
                    let faces = replayBaseline.compactMap { $0.face }
                    replayMainFixture = (Self.medianRect(replayBaseline.map { $0.box }),
                                         faces.count * 2 >= replayBaseline.count ? Self.median(faces) : nil)
                }
            }
        }
        let needsSensors = result.activeStep != nil && result.activeStep != .distance
        let ready = result.activeStep == nil && result.instruction == .holdStill
        let shown: GuideInstruction = needsSensors || ready ? .findPerson : result.instruction
        replayMaskNote = needsSensors || ready
            ? "\(result.activeStep?.title ?? "Ready") not evaluated in Replay (no motion sensor / field of view)"
            : nil
        replayRecorder?.instruction(needsSensors || ready ? "notEvaluated" : String(describing: shown), at: now)
        return shown
    }

    /// Zoom the guide asked for (never applied to a video).
    func replayZoomIntent(_ zoom: Double, now: TimeInterval) {
        replayRecorder?.zoomIntent(zoom, at: now)
    }
}
