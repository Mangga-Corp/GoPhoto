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
}

@Observable
final class CameraViewModel {

    // MARK: State the View reads
    private(set) var state: CameraState = .idle
    private(set) var capturedImage: UIImage?
    private(set) var isCapturing = false
    private(set) var errorMessage: String?

    private(set) var tiltDegrees: Int?
    
    var isLevel: Bool { tiltDegrees == 0}
    
    var isShowingError: Bool {
        get { errorMessage != nil }
        set { if !newValue { errorMessage = nil } }
    }

    var session: AVCaptureSession { cameraService.session }

    // MARK: Dependency (injected, like swiftshop's repositories)
    @ObservationIgnored private let cameraService: CameraServiceProtocol
    @ObservationIgnored private let motionService: MotionServiceProtocol

    init(cameraService: CameraServiceProtocol = CameraService(),
         motionService: MotionServiceProtocol = MotionService()) {
        self.cameraService = cameraService
        self.motionService = motionService
    }

    // MARK: Intents (things the View asks for)

    func startCamera() async {
        guard await cameraService.requestPermission() else {
            state = .permissionDenied
            return
        }
        do {
            try await cameraService.configure()
            await cameraService.start()
            state = .running
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
    
    func observeTilt() async {
        for await tilt in motionService.tiltUpdates() {
            let newValue: Int? = abs(tilt.pitch) > 75 ?
                nil : Int(abs(tilt.roll).rounded())
            
            if newValue != tiltDegrees {
                tiltDegrees = newValue
            }
        }
    }

    func stopCamera() async {
        await cameraService.stop()
    }

    func takePhoto() async {
        guard state == .running, !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            capturedImage = try await cameraService.capturePhoto()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retake() {
        capturedImage = nil
    }
}
