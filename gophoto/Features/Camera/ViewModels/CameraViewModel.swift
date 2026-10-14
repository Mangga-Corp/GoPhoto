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
    private(set) var target: FramingTarget = .center   // later: from AI preferences
    private(set) var personOutline: CGImage?
    private(set) var instruction: GuideInstruction = .findPerson
    var isReady: Bool { instruction == .holdStill }      // "green"

    @ObservationIgnored private var personBox: CGRect?   // logic only, never drawn
    @ObservationIgnored private var roll: Double = 0     // logic only, never drawn

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

    init(cameraService: CameraServiceProtocol = CameraService(),
         motionService: MotionServiceProtocol = MotionService(),
         photoLibraryService: PhotoLibraryServiceProtocol = PhotoLibraryService(),
         galleryStore: GalleryStoreProtocol? = nil){
        self.cameraService = cameraService
        self.motionService = motionService
        self.photoLibraryService = photoLibraryService
        self.galleryStore = galleryStore ?? GalleryStore()
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
        let next = GuideInstruction.next(offset: personBox.map(target.offset(of:)),
                                         roll: roll,
                                         current: instruction)
        if next != instruction {
            instruction = next
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
