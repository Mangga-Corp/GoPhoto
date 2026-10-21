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
    private(set) var personOutline: CGImage?
    private(set) var instruction: GuideInstruction = .findPerson
    var isReady: Bool { instruction == .holdStill }      // "green"

    // Live values. Observable so the debug panel can show them; the guide UI does not read them.
    private(set) var personBox: CGRect?                  // normalized, origin top-left
    private(set) var roll: Double = 0                    // + = rotated clockwise
    private(set) var pitch: Double = 0                   // + = phone tilted down

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
            // Drawing: skip nil → nil writes (nobody in view)
            let newOutline = detection?.outline
            if newOutline != nil || personOutline != nil {
                personOutline = newOutline
            }

            // Logic
            personBox = detection?.box
            updateInstruction()
        }
        personOutline = nil
        personBox = nil
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

        let next = GuideInstruction.next(offset: personBox.map(target.offset(of:)),
                                         roll: roll,
                                         pitchError: pitchError,
                                         current: instruction)
        if next != instruction {
            instruction = next
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
