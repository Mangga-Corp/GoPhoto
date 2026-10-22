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
    @ObservationIgnored private var verticalFOV: Double? // of the upright frame, degrees
    @ObservationIgnored private var photoMegapixels: Double? // largest photo size (mode F)

    // Guide variant under test (debug panel). Saved across launches.
    var guideMode: GuideMode = GuideMode.saved() {
        didSet {
            UserDefaults.standard.set(guideMode.rawValue, forKey: GuideMode.storageKey)
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
         preferences: PreferencesViewModel? = nil){
        self.cameraService = cameraService
        self.motionService = motionService
        self.photoLibraryService = photoLibraryService
        self.galleryStore = galleryStore ?? GalleryStore()
        self.preferences = preferences ?? .shared
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
            updateInstruction()
        }
        personBox = nil
        personOutline = nil
        face = nil
        instruction = .findPerson
    }

    private func updateInstruction() {
        // Targets come from the selected preset, so switching presets applies at once.
        let preset = preferences.selectedPreference
        if preset?.id != presetID { presetID = preset?.id }
        if preset?.name != presetName { presetName = preset?.name }
        if preset?.analysis != analysis { analysis = preset?.analysis }
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

        case .heightFirst, .heightFirstCrop, .tiltFirst, .currentSteps, .currentStepsHeight, .fixedRules, .wideCrop:
            let live = GuideLive(person: personBox, face: face, verticalFOV: verticalFOV, roll: roll, pitch: pitch,
                                 photoMegapixels: photoMegapixels)
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
        await cameraService.stop()
    }

    func takePhoto() async {
        guard state == .running, !isCapturing else { return }
        isCapturing = true

        // Mode F: remember where the person is and how the phone is turned at the shutter.
        let cropPlan: (person: CGRect, target: CGRect, roll: Double, megapixels: Double?)? =
            guideMode.crops ? personBox.map { ($0, target.rect, roll, photoMegapixels) } : nil

        let photo: CapturedPhoto
        do {
            photo = try await cameraService.capturePhoto()
        } catch {
            isCapturing = false
            errorMessage = error.localizedDescription
            return
        }
        isCapturing = false
        captureCount += 1

        do {
            if let assetID = try await photoLibraryService.save(imageData: photo.data) {
                galleryStore.addCaptured(assetID: assetID, presetID: nil)
            }
            // Crop modes (testing): also save the cropped, straightened version next to the original.
            if let plan = cropPlan {
                let data = photo.data
                let cropped = await Task.detached(priority: .userInitiated) {
                    WideCrop.crop(data, person: plan.person, target: plan.target,
                                  rollDegrees: plan.roll, photoMegapixels: plan.megapixels)
                }.value
                if let cropped, let assetID = try await photoLibraryService.save(imageData: cropped) {
                    galleryStore.addCaptured(assetID: assetID, presetID: nil)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
