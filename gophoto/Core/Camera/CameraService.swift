//
//  CameraService.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//

//
//  CameraService.swift
//  gophoto
//
//  Core layer: the ONLY place that talks to camera hardware.
//  Same role as a Repository in swiftshop, but for hardware instead of network.
//

import AVFoundation
import UIKit
import CoreMedia

// MARK: - Model

/// A photo straight from iPhone Camera
nonisolated struct CapturedPhoto: Sendable {
    let data: Data      // Original file-data (HEIC/ JPEG + metadata) -> For saving to phone
    let image: UIImage  // Decoded image -> for showing on screen (view -> iPhone screen)
}


// MARK: - Errors

nonisolated enum CameraError: LocalizedError {
    case cameraUnavailable
    case cannotAddInput
    case cannotAddOutput
    case captureInProgress
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable: return "No camera found. (The Simulator has no camera — run on a real iPhone.)"
        case .cannotAddInput:    return "Couldn't connect to the camera."
        case .cannotAddOutput:   return "Couldn't set up photo capture."
        case .captureInProgress: return "Already taking a photo."
        case .captureFailed:     return "Couldn't process the photo."
        }
    }
}

// MARK: - Protocol (the "contract" the ViewModel depends on)

nonisolated protocol CameraServiceProtocol: AnyObject {
    var session: AVCaptureSession { get }
    func requestPermission() async -> Bool
    func configure() async throws
    func start() async
    func stop() async
    func capturePhoto() async throws -> CapturedPhoto
    func personDetections() -> AsyncStream<PersonDetection?>
}

// MARK: - Real implementation

nonisolated final class CameraService: NSObject, CameraServiceProtocol, @unchecked Sendable {

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "gophoto.camera.session")
    private var isConfigured = false
    private var photoContinuation: CheckedContinuation<CapturedPhoto, Error>?
    
    // for the apple vision framework
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "gophoto.camera.video")
    private let personDetector = PersonDetector()
    private var personContinuation: AsyncStream<PersonDetection?>.Continuation?
    private var frameCount = 0                                                      

    // 1. Ask the user for camera permission (shows the iOS popup the first time)
    func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default:             return false   // .denied or .restricted
        }
    }

    // 2. Connect back camera (input) and photo output to the session
    func configure() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // 3. Start / stop the live camera feed
    func start() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if !self.session.isRunning { self.session.startRunning() }
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.session.isRunning { self.session.stopRunning() }
                continuation.resume()
            }
        }
    }

    // 4. Take a photo. The delegate callback below finishes this.
    func capturePhoto() async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                guard self.photoContinuation == nil else {
                    continuation.resume(throwing: CameraError.captureInProgress)
                    return
                }
                self.photoContinuation = continuation

                // Portrait photo
                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }
    
    // Stream of "where is the person" (nil = nobody). Detection only runs while someone listens.
    func personDetections() -> AsyncStream<PersonDetection?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            videoQueue.async { self.personContinuation = continuation }

            continuation.onTermination = { _ in
                self.videoQueue.async { self.personContinuation = nil }
            }
        }
    }

    private func configureSession() throws {
        guard !isConfigured else { return }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)
        
        // live video frames → person detection
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90   // upright frames, same as the photo
        }

        isConfigured = true
    }
}

// MARK: - Photo delegate (AVFoundation calls this when the photo is ready)

nonisolated extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let result: Result<CapturedPhoto, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(CapturedPhoto(data: data, image: image))
        } else {
            result = .failure(CameraError.captureFailed)
        }

        sessionQueue.async {
            self.photoContinuation?.resume(with: result)
            self.photoContinuation = nil
        }
    }
}

// MARK: - Video frame delegate (called ~30x/sec on videoQueue)

nonisolated extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let continuation = personContinuation else { return }

        frameCount += 1
        guard frameCount.isMultiple(of: 2),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        continuation.yield(personDetector.detect(in: pixelBuffer))           
    }
}
