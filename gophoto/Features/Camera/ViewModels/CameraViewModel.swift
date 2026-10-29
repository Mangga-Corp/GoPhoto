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
    private(set) var personOutline: CGImage?             // body outline, old-look mode only
    private(set) var exposure: ExposureStatus?           // backlight tip / ISO / shutter (debug panel)
    let lighting = LightingCoordinator()                 // sun / light tips; the camera owns the exposure
    @ObservationIgnored private var verticalFOV: Double? // of the upright frame, degrees
    @ObservationIgnored private var photoMegapixels: Double? // largest photo size (mode F)

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
            cameraService.setOutlineEnabled(guideMode == .currentOldLook)
            cameraService.setHighResolution(guideMode.crops)
            progress = GuideProgress()
            updateInstruction()
        }
    }
    /// Steps, checks and measurements of the current frame (modes B and C fill the checks).
    private(set) var evaluation = GuideEvaluation()
    @ObservationIgnored private var progress = GuideProgress()
    /// Keep finished steps done (no going back over small wobbles). Debug-panel toggle.
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
    @ObservationIgnored private var stillFrames: [(person: CGRect, face: CGRect?, pitch: Double)] = []
    @ObservationIgnored private var snapshot: (person: CGRect, face: CGRect?, pitch: Double)?
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
        guard isPhoneStill else { return }
        stillFrames.append((box, face, pitch))
        if stillFrames.count > Self.snapshotSize { stillFrames.removeFirst(stillFrames.count - Self.snapshotSize) }
        let faces = stillFrames.compactMap { $0.face }
        // A face only counts when it was found in at least half of the still frames.
        let medianFace: CGRect? = faces.count * 2 >= stillFrames.count ? Self.medianRect(faces) : nil
        snapshot = (person: Self.medianRect(stillFrames.map { $0.person }),
                    face: medianFace,
                    pitch: Self.median(stillFrames.map { $0.pitch }))
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

    // The selected preset and what the AI learned from it (copied from PreferencesViewModel).
    private(set) var presetName: String?
    private(set) var presetID: UUID?
    private(set) var analysis: PresetAnalysis?
    private(set) var isAnalyzingPreset = false

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
        let heightOK = e.eyeElevation.flatMap { now in
            e.eyeElevationTarget.map { abs(now - $0) <= GuideFlow.heightEnter }
        } ?? true
        let tiltOK = pitchError.map { abs($0) <= GuideFlow.tiltEnter } ?? true
        return PoseGuideState(heightNow: centimetres(e.eyeElevation),
                              heightTarget: centimetres(e.eyeElevationTarget),
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
         fixedSetup: (mode: GuideMode, aspect: CaptureAspect)? = nil){
        self.cameraService = cameraService
        self.motionService = motionService
        self.photoLibraryService = photoLibraryService
        self.galleryStore = galleryStore ?? GalleryStore()
        self.preferences = preferences ?? .shared
        if let fixedSetup {   // testing mode: fixed, not saved
            savesSetup = false
            guideMode = fixedSetup.mode
            captureAspect = fixedSetup.aspect
        }
        self.cameraService.setOutlineEnabled(guideMode == .currentOldLook)
        self.cameraService.setHighResolution(guideMode.crops)
    }

    // MARK: Intents (things the View asks for)

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
            if next != horizon {
                horizon = next
            }
            updateInstruction()
        }
        horizon = .hidden
    }

    // listens to person detection until the View's .task is cancelled
    func observePerson() async {
        for await detection in cameraService.personDetections() {
            personBox = detection?.box
            if detection?.outline != nil || personOutline != nil { personOutline = detection?.outline }
            face = detection?.face
            if let fov = detection?.verticalFOV { verticalFOV = fov }
            if let mp = detection?.photoMegapixels { photoMegapixels = mp }
            recordDetection()
            updateInstruction()
        }
        personBox = nil
        personOutline = nil
        face = nil
        instruction = .findPerson
    }

    /// Listens to the camera's exposure readings until the View's .task is cancelled.
    func observeExposure() async {
        for await status in cameraService.exposureStatus() {
            exposure = status
            lighting.ingest(status, hasPerson: personBox != nil)
        }
        exposure = nil
        lighting.reset()
    }

    private func updateInstruction() {
        // Targets come from the selected preset, so switching presets applies at once.
        let preset = preferences.selectedPreference
        if preset?.id != presetID { presetID = preset?.id }
        if preset?.name != presetName { presetName = preset?.name }
        let picked = preset?.analysis?.forFraming(preferences.effectiveFraming(for: preset))
        if picked != analysis { analysis = picked }
        lighting.setLightLevel(preset?.analysis?.lightLevel)
        let analyzing = preset.map { preferences.isAnalyzing($0.id) } ?? false
        if analyzing != isAnalyzingPreset { isAnalyzingPreset = analyzing }

        let newTarget = analysis?.subjectBox.map { FramingTarget(rect: $0) } ?? .center
        if newTarget != target {
            target = newTarget
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
            let live = GuideLive(person: snap?.person ?? personBox, face: snap.map { $0.face } ?? face,
                                 verticalFOV: verticalFOV, roll: roll, pitch: pitch,
                                 photoMegapixels: photoMegapixels, measurePitch: snap?.pitch)
            let (result, nextProgress) = GuideFlow.evaluate(
                mode: guideMode, live: live, analysis: analysis, target: target, targetPitch: targetPitch,
                progress: progress, latch: latchSteps, now: ProcessInfo.processInfo.systemUptime)
            progress = nextProgress
            if result != evaluation { evaluation = result }

            // Size is smoothed in log space so "2x too close" and "2x too far" behave alike.
            barSizeRatio = smoothed("size", result.sizeRatio.map { log($0) }).map { exp($0) }
            let heightError: Double? = {
                guard let now = result.eyeElevation, let target = result.eyeElevationTarget else { return nil }
                return now - target
            }()
            barHeightError = smoothed("height", heightError)
            barTiltError = smoothed("tilt", pitchError)
            if result.instruction != instruction {
                instruction = result.instruction
            }
        }
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

    func stopCamera() async {
        lighting.reset()
        await cameraService.stop()
    }

    /// Restarts the feed after `stopCamera()` (the session is already set up).
    func resumeCamera() async {
        guard state == .running else { return }
        await cameraService.start()
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

        // Mode F: remember where the person is and how the phone is turned at the shutter.
        // Half body (preset cut at the bottom): the crop follows the torso, see `WideCrop.TorsoTarget`.
        let torsoTarget: WideCrop.TorsoTarget? = analysis?.clippedBottom == true
            ? analysis.flatMap { a in
                a.halfBodyNeck.flatMap { neck in a.halfBodyTorso.map { WideCrop.TorsoTarget(neck: neck, torso: $0) } }
            }
            : nil
        let cropPlan: (person: CGRect, target: CGRect, torso: WideCrop.TorsoTarget?, roll: Double, megapixels: Double?)? =
            guideMode.crops ? personBox.map { ($0, target.rect, torsoTarget, roll, photoMegapixels) } : nil

        let photo: CapturedPhoto
        let shutterAt = Date()
        do {
            // Flash + free the shutter at the moment the photo is taken, not when the (48 MP)
            // file is ready: with zero shutter lag that moment is the tap.
            photo = try await cameraService.capturePhoto(onShutter: { [weak self] in
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

        // One photo per shot, made in the background so the shutter is free: crop modes crop
        // (from the full 4:3 frame, where the plan's coordinates are), other ratios crop to
        // 1:1 / 16:9. No auto enhance: filters are applied later from the gallery by the user.
        // Without a crop the camera's file is saved as is (no re-encode).
        let original = photo.data
        let aspect = captureAspect
        let ratio = aspect.ratio
        Task { [weak self] in
            let (finished, cropSeconds) = await Task.detached(priority: .userInitiated) {
                () -> (Data, Double?) in
                let cropStart = Date()
                if let plan = cropPlan {
                    let cropped = WideCrop.crop(original, person: plan.person, target: plan.target,
                                                torsoTarget: plan.torso, rollDegrees: plan.roll,
                                                photoMegapixels: plan.megapixels) ?? original
                    return (cropped, Date().timeIntervalSince(cropStart))
                }
                if aspect != .fourThree {
                    let cropped = CapturedPhotoEnhancing.cropped(original, aspect: ratio) ?? original
                    return (cropped, Date().timeIntervalSince(cropStart))
                }
                return (original, nil)
            }.value
            guard let self else { return }
            let saveStart = Date()
            do {
                if let assetID = try await self.photoLibraryService.save(imageData: finished) {
                    self.galleryStore.addCaptured(assetID: assetID, presetID: nil)
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            let crop = cropSeconds.map { String(format: " · crop %.2fs", $0) } ?? ""
            self.lastShotTiming = String(format: "shutter %.2fs · file %.2fs", self.shutterSeconds, captureSeconds) + crop
                + String(format: " · save %.2fs", Date().timeIntervalSince(saveStart))
        }
    }
      

    /// Saves the reviewed photo: the enhanced version (the original if the enhance failed),
    /// plus the cropped version in crop modes. Closes the review when done.
    func saveReview() async {
        guard let review, !review.isEnhancing, !isSavingReview else { return }
        isSavingReview = true
        defer { isSavingReview = false }

        let original = review.photo.data
        let enhanced = review.enhanced
        let data = await Task.detached(priority: .userInitiated) {
            enhanced.flatMap { CapturedPhotoEnhancing.file(for: $0, metadataFrom: original) } ?? original
        }.value

        do {
            if let assetID = try await photoLibraryService.save(imageData: data) {
                galleryStore.addCaptured(assetID: assetID, presetID: nil)
            }
            // Crop modes (testing): also save the cropped, straightened version next to it.
            if let plan = review.cropPlan {
                let cropped = await Task.detached(priority: .userInitiated) {
                    WideCrop.crop(data, person: plan.person, target: plan.target,
                                  rollDegrees: plan.roll, photoMegapixels: plan.megapixels)
                }.value
                if let cropped, let assetID = try await photoLibraryService.save(imageData: cropped) {
                    galleryStore.addCaptured(assetID: assetID, presetID: nil)
                }
            }
            if self.review?.id == review.id { self.review = nil }
        } catch {
            self.review?.saveError = error.localizedDescription
        }
    }

    /// Discards the reviewed photo and returns to the viewfinder.
    func retake() {
        enhanceTask?.cancel()
        enhanceTask = nil
        review = nil
    }
}
