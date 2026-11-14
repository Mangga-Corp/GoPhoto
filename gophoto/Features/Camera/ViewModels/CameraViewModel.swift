//
//  CameraViewModel.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//  13 Nov (Reynard): production camera only — Phased · Auto crop. Everything developer-only (experiment
//  picker, old guides Main / Main modified, auto-zoom, replay, guide log, GT recording, depth, Blur On,
//  debug panel, pose guide) moved to the debugphoto repo (Lab), which keeps its own copy of this
//  feature folder and uses the same Core (CameraService, PersonDetector, Phased engine).
//  The previous version is in `_to_delete/pra-bersih-debug/`.
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

    // Live sensor values the guide reads.
    private(set) var roll: Double = 0                    // + = rotated clockwise
    private(set) var pitch: Double = 0                   // + = phone tilted down
    @ObservationIgnored private var verticalFOV: Double? // of the upright frame, degrees
    @ObservationIgnored private var photoMegapixels: Double?

    var isLevel: Bool { horizon == .level }

    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var session: AVCaptureSession { cameraService.session }

    // MARK: Zoom settling (boxes are only comparable within one zoom)

    @ObservationIgnored private var lastFrameZoom: Double?
    @ObservationIgnored private var zoomQuietSince: TimeInterval?
    private static let zoomSettle: TimeInterval = 0.3

    private func recordZoom(_ detection: PersonDetection?, now: TimeInterval) {
        guard let zoom = detection?.zoomFactor else { return }
        let changed = lastFrameZoom.map { abs(zoom - $0) / $0 > 0.01 } ?? false
        lastFrameZoom = zoom
        if changed || detection?.isZooming == true {
            zoomQuietSince = nil
        } else if zoomQuietSince == nil {
            zoomQuietSince = now
        }
    }

    private func zoomSettled(now: TimeInterval) -> Bool {
        zoomQuietSince.map { now - $0 >= Self.zoomSettle } ?? (lastFrameZoom == nil)
    }

    // MARK: Phone still (the engine reads it)

    /// The phone has not turned more than `stillTolerance` degrees for `stillWindow` seconds.
    private(set) var isPhoneStill = false
    @ObservationIgnored private var motionSamples: [(t: TimeInterval, pitch: Double, roll: Double)] = []
    private static let stillWindow: TimeInterval = 0.3
    private static let stillTolerance = 1.0

    private func recordMotion(pitch: Double, roll: Double) {
        let now = clockNow
        motionSamples.append((now, pitch, roll))
        motionSamples.removeAll { now - $0.t > Self.stillWindow + 0.1 }
        let span = (motionSamples.last?.t ?? now) - (motionSamples.first?.t ?? now)
        let pitches = motionSamples.map { $0.pitch }, rolls = motionSamples.map { $0.roll }
        let steady = (pitches.max() ?? 0) - (pitches.min() ?? 0) < Self.stillTolerance
            && (rolls.max() ?? 0) - (rolls.min() ?? 0) < Self.stillTolerance
        let still = span >= Self.stillWindow && steady
        if still != isPhoneStill { isPhoneStill = still }
    }

    private var clockNow: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Phased state

    /// The Phased engine's decision this update (crop window, readiness, bars).
    private(set) var phased = PhasedOutput()
    /// The photo shape the preview shows and the shutter saves (3:4 by default). Kept for this
    /// camera session only: a new session (a new camera screen) starts at 3:4 again.
    private(set) var aspectRatio: CameraAspectRatio = .threeFour
    /// The one instruction shown: choosing / finding the subject first, then the engine's.
    private(set) var phasedInstruction: PhasedInstruction?
    /// Selection UI: dims everything but people (nil = no dimming).
    private(set) var selectionDimMask: CGImage?
    /// A phase just finished: green confirmation for about a second ("Distance ✓"), else nil.
    private(set) var phasedFlash: String?
    @ObservationIgnored private var phasedFlashID = 0
    @ObservationIgnored private var phasedEngine: PhasedEngine?
    @ObservationIgnored private var phasedEngineSourceMP: Double?
    @ObservationIgnored private var selector = PhasedSubjectPicker()
    @ObservationIgnored private var phasedCandidates: [CGRect] = []
    @ObservationIgnored private var phasedSubject: SubjectObservation?
    @ObservationIgnored private var phasedDetectionTime: TimeInterval?
    @ObservationIgnored private var phasedLockedBox: CGRect?
    @ObservationIgnored private var phasedSubjectLocked = false
    @ObservationIgnored private var phasedZooming = false
    /// Last zoom asked of the camera (one request per target; the ramp then runs on its own).
    @ObservationIgnored private var phasedZoomTarget: (zoom: Double, at: TimeInterval)?
    @ObservationIgnored private var phasedLandmarks: (marks: [BodyLandmark], at: TimeInterval)?
    @ObservationIgnored private var phasedExtent: (box: CGRect, edges: FrameEdges, at: TimeInterval)?
    @ObservationIgnored private var dimmingOn = false
    @ObservationIgnored private var lockRequested: CGRect?

    /// The photo is ready to take ("Take the photo now").
    var isReady: Bool { phased.ready }

    // MARK: Session, preset and shot size

    /// The session the camera guides with, set by the view (`apply(sessionConfiguration:)`).
    /// The camera never picks a preference itself; the session's shot size is the picker's first
    /// selection. Nil = no preset.
    private(set) var sessionConfiguration: PhotoSessionConfiguration?
    private(set) var presetName: String?
    private(set) var presetID: UUID?
    /// The whole preset analysis (all shot sizes), for the shot size picker.
    private(set) var presetAnalysis: PresetAnalysis?
    /// The analysis guiding now: the picked shot size for the person's posture.
    private(set) var analysis: PresetAnalysis?

    /// Sitting / standing, smoothed over the last pose readings. Nil until read (or after the
    /// person was lost): treated like standing.
    private(set) var posture: BodyPosture?
    /// The photographer's pick among the standing shot sizes. Starts at the session's shot size.
    private(set) var selectedShot: PresetAnalysis.ShotSize?
    @ObservationIgnored private var postureReadings: [BodyPosture] = []
    @ObservationIgnored private var personMissingSince: TimeInterval?
    private static let postureWindow = 6
    private static let postureSwitchVotes = 4
    private static let postureFirstVotes = 3
    /// Posture is forgotten after the person has been gone this long.
    private static let postureLostReset: TimeInterval = GuideFlow.lostReset

    /// What the picker offers now: sitting → full body only; standing → the preset's shot sizes
    /// (one-quarter is not supported by the Phased guide yet).
    var shotOptions: [PresetAnalysis.ShotSize] {
        (presetAnalysis?.shotOptions(for: posture) ?? []).filter { $0 != .quarter }
    }

    /// The shot size guiding now: the pick when it is offered, else the preset's default, else the first option.
    var activeShot: PresetAnalysis.ShotSize? {
        let options = shotOptions
        if let selectedShot, options.contains(selectedShot) { return selectedShot }
        if let fallback = presetAnalysis?.defaultShot, options.contains(fallback) { return fallback }
        return options.first
    }

    /// Shown above the shot sizes when the preset has one-quarter photos.
    var phasedShotNote: String? {
        guard presetAnalysis?.availableShots.contains(.quarter) == true else { return nil }
        return "1/4 isn't available yet"
    }

    /// A pick in the shot size picker: the guide starts over with that shot size.
    func selectShot(_ shot: PresetAnalysis.ShotSize) {
        guard shotOptions.contains(shot), shot != selectedShot else { return }
        selectedShot = shot
        updateInstruction()
    }

    private func recordPosture(_ reading: BodyPosture?, personVisible: Bool) {
        let now = clockNow
        guard personVisible else {
            let since = personMissingSince ?? now
            personMissingSince = since
            if now - since >= Self.postureLostReset {
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

    // MARK: Dependency (injected)
    @ObservationIgnored private let cameraService: CameraServiceProtocol
    @ObservationIgnored private let motionService: MotionServiceProtocol
    @ObservationIgnored private let photoLibraryService: PhotoLibraryServiceProtocol
    @ObservationIgnored private let galleryStore: GalleryStoreProtocol
    @ObservationIgnored private let preferences: PreferencesViewModel
    private var camera: CameraServiceProtocol { cameraService }

    init(cameraService: CameraServiceProtocol = CameraService(),
         motionService: MotionServiceProtocol = MotionService(),
         photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
         galleryStore: GalleryStoreProtocol? = nil,
         preferences: PreferencesViewModel? = nil,
         sessionConfiguration: PhotoSessionConfiguration? = nil) {
        self.cameraService = cameraService
        self.motionService = motionService
        self.photoLibraryService = photoLibraryService
        self.galleryStore = galleryStore ?? GalleryStore()
        self.preferences = preferences ?? .shared
        self.sessionConfiguration = sessionConfiguration
        // Phased · Auto crop: largest photo size at 1× (it crops), strict subject lock.
        cameraService.setOutlineEnabled(false)
        cameraService.setHighResolution(true)
        cameraService.setStrictSubjectLock(true)
        phasedEngine = makePhasedEngine()
    }

    // MARK: Intents (things the View asks for)

    /// A new session (or none): the guide starts over with its preset and effective shot size.
    func apply(sessionConfiguration configuration: PhotoSessionConfiguration?) {
        guard configuration != sessionConfiguration else { return }
        sessionConfiguration = configuration
        selectedShot = configuration?.effectiveShotSize
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
            // Auto crop never zooms: 1× for the whole guide.
            _ = await camera.applyZoom(1)
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
            roll = tilt.roll
            pitch = tilt.pitch
            recordMotion(pitch: tilt.pitch, roll: tilt.roll)
            let next = HorizonState.next(roll: tilt.roll, pitch: tilt.pitch, current: horizon)
            if next != horizon { horizon = next }
            updateInstruction()
        }
        horizon = .hidden
    }

    /// Listens to person detection until the View's .task is cancelled.
    func observePerson() async {
        for await detection in camera.personDetections() {
            let subjectSeen = detection != nil && detection?.subjectLocked != false
            let now = clockNow
            recordPhasedDetection(detection, now: now)
            recordZoom(detection, now: now)
            if let fov = detection?.verticalFOV { verticalFOV = fov }
            if let mp = detection?.photoMegapixels { photoMegapixels = mp }
            recordPosture(detection?.posture, personVisible: subjectSeen)
            updateInstruction()
        }
    }

    func observeZoom() async {
        for await zoom in camera.zoomUpdates() {
            let label = zoom.flatMap { value -> String? in
                guard value.isFinite, value > 0 else { return nil }
                return String(format: "%.1f×", value)
            }
            if label != currentZoomLabel { currentZoomLabel = label }
        }
        currentZoomLabel = nil
    }

    /// Targets come from the session's preset and the shot size picked in the camera for the
    /// person's posture (read live, so a finished analysis applies at once). A deleted preset
    /// means no preset targets: another preset is never substituted here.
    private func updateInstruction() {
        let session = sessionConfiguration
        let preset = session.flatMap { preferences.preference(id: $0.preferenceID) }
        if preset?.id != presetID { presetID = preset?.id }
        if preset?.name != presetName { presetName = preset?.name }
        let whole = session == nil ? nil : preset?.analysis
        if whole != presetAnalysis { presetAnalysis = whole }
        let picked = activeShot.flatMap { whole?.guide(for: $0, posture: posture) }
        if picked != analysis { analysis = picked }
        updatePhased()
    }

    func stopCamera() async {
        await camera.stop()
    }

    /// Restarts the feed after `stopCamera()` (the session is already set up).
    func resumeCamera() async {
        guard state == .running else { return }
        await camera.start()
    }

    // MARK: Capture

    /// The photo was taken: flash, haptic and a free shutter (its file is still processing).
    private func shutterFired() {
        guard isCapturing else { return }
        isCapturing = false
        captureCount += 1
    }

    func takePhoto() async {
        guard state == .running, !isCapturing else { return }
        isCapturing = true
        // The crop at the shutter: the final crop when ready; before that the crop valid right now
        // (shaky hands still get a framed photo). Nothing measurable yet = the full photo.
        let wanted = shutterCrop()
        let aspectAtShot = aspectRatio
        let photo: CapturedPhoto
        do {
            photo = try await camera.capturePhoto(onShutter: { [weak self] in
                Task { @MainActor in self?.shutterFired() }
            })
        } catch {
            isCapturing = false
            errorMessage = error.localizedDescription
            return
        }
        shutterFired()                                    // no-op if the shutter callback came first

        let capturedData = photo.data
        let presetAtShot = presetID
        Task { [weak self] in
            guard let self else { return }
            // Only the crop is saved (Reynard, 9 Nov). The full photo is saved only when no crop
            // was made (nothing measurable yet, or the export failed).
            var savedCrop = false
            if let wanted {
                savedCrop = await self.savePhasedCrop(of: capturedData, crop: wanted.rect, roll: wanted.roll,
                                                      floor: wanted.floor, aspect: aspectAtShot,
                                                      presetID: presetAtShot)
            }
            if !savedCrop { await self.saveFull(capturedData, presetID: presetAtShot) }
        }
    }

    private func shutterCrop() -> (rect: CGRect, roll: Double, floor: Double)? {
        let floor = PhasedParameters.standard.cropFloorMegapixels
        guard let window = phased.cropWindow ?? phased.captureCrop else {
            // Nothing measurable yet: 3:4 saves the whole photo; a narrower ratio still saves
            // exactly what the preview shows (its band of the frame).
            if aspectRatio.showsWholeFrame { return nil }
            return (rect: aspectRatio.visibleRect, roll: 0, floor: floor)
        }
        return (window, phased.cropWindow != nil ? phased.cropRoll : phased.captureRoll, floor)
    }

    /// The ratio picker: the preview, the guide's crop and the next photo follow at once (the
    /// camera session keeps running; the guide keeps its progress).
    func selectAspectRatio(_ ratio: CameraAspectRatio) {
        guard ratio != aspectRatio else { return }
        aspectRatio = ratio
        guard var engine = phasedEngine else { return }
        engine.cropShape = ratio.cropShape
        phasedEngine = engine
        updatePhased()   // the shutter crop follows the new shape before the next frame
    }

    /// Saves the Auto crop as THE photo. False = not saved (no crop made or the save failed).
    private func savePhasedCrop(of data: Data, crop: CGRect, roll: Double, floor: Double,
                                aspect: CameraAspectRatio, presetID presetAtShot: UUID?) async -> Bool {
        // 3:4: the original crop (the frame's own shape). Narrower: exactly that shape, inside
        // the band the preview showed.
        let bounds = aspect.visibleRect
        let shape: (width: Int, height: Int)? = aspect.showsWholeFrame ? nil : aspect.units
        let result = await Task.detached(priority: .userInitiated) {
            PhasedCrop.apply(imageData: data, crop: crop, rollDegrees: roll, floorMegapixels: floor,
                             bounds: bounds, outputShape: shape)
        }.value
        guard let cropped = result.data else { return false }
        let thumbnail = Self.makeThumbnail(of: cropped)
        do {
            if let assetID = try await photoLibraryService.save(imageData: cropped) {
                await Self.storeThumbnail(thumbnail, for: assetID)
                galleryStore.addCaptured(assetID: assetID, presetID: presetAtShot)
                return true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    private func saveFull(_ data: Data, presetID presetAtShot: UUID?) async {
        let thumbnail = Self.makeThumbnail(of: data)
        do {
            if let assetID = try await photoLibraryService.save(imageData: data) {
                await Self.storeThumbnail(thumbnail, for: assetID)   // before the grid shows it
                galleryStore.addCaptured(assetID: assetID, presetID: presetAtShot)
            }
        } catch {
            errorMessage = error.localizedDescription
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
}

// MARK: - Phased guide
//
// The engine (Core/Guide/Phased) decides; this glue feeds it the locked subject and sensors, shows
// its one instruction and the subject choice. Spec: Docs/Experiments/PhaseGuide/Spec-v3.md.

extension CameraViewModel {

    private func makePhasedEngine() -> PhasedEngine {
        let params = PhasedParameters.standard
        let minScale = PhasedMeasure.cropMinScale(sourceMP: photoMegapixels, floorMP: params.cropFloorMegapixels)
        phasedEngineSourceMP = photoMegapixels
        var engine = PhasedEngine(params: params, policy: .autoCrop, zoomPlan: .fixedOne, cropMinScale: minScale)
        engine.cropShape = aspectRatio.cropShape
        return engine
    }

    /// Called for every detection.
    private func recordPhasedDetection(_ detection: PersonDetection?, now: TimeInterval) {
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
        if let extent = d.extent { phasedExtent = (extent, d.extentEdges, now) }
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

    /// One update of the guide (every detection and every motion update).
    private func updatePhased() {
        guard var engine = phasedEngine else { return }
        let now = clockNow
        // The crop floor depends on the real photo size, known after the first frames.
        if let mp = photoMegapixels, phasedEngineSourceMP != mp {
            engine = makePhasedEngine()
        }
        var events: [PhasedEvent] = []
        let made = PhasedTarget.make(analysis: analysis, shot: activeShot, posture: posture)
        events += engine.setTarget(made.target, problem: made.reason)
        let selection = selector.update(candidates: phasedCandidates, locked: phasedSubjectLocked,
                                        lockedBox: phasedLockedBox, now: now)
        handleSelection(selection, engine: &engine, events: &events)

        let frame = PhasedFrame(time: now,
                                subject: phasedSubjectLocked ? phasedSubject : nil,
                                detectionTime: phasedDetectionTime,
                                pitch: pitch, roll: roll,
                                phoneStill: isPhoneStill,
                                verticalFOV: verticalFOV, zoom: lastFrameZoom,
                                zoomStable: zoomSettled(now: now) && !phasedZooming,
                                nativeTwoX: camera.nativeZoomFactors.contains { abs($0 - 2) < 0.05 },
                                depth: nil)
        let (out, more) = engine.step(frame)
        events += more
        phasedEngine = engine
        // Engine zoom (always 1× for Auto crop): also pulls the zoom back if something else moved it.
        if let zoom = out.zoomRequest { requestPhasedZoom(zoom, now: now) }

        let final: PhasedInstruction? = selection.instruction ?? (phasedSubjectLocked ? out.instruction : nil)
        if out != phased { phased = out }
        if final != phasedInstruction { phasedInstruction = final }
        for event in events where event.kind == "phase" { flashPhaseDone(event.detail) }
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
        guard phasedInstruction == .tapPerson, var engine = phasedEngine else { return }
        var events: [PhasedEvent] = []
        let s = selector.tap(point, candidates: phasedCandidates)
        handleSelection(s, engine: &engine, events: &events)
        setDimming(false)
        phasedEngine = engine
    }

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
}
