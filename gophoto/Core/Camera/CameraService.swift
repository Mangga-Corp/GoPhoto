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

/// Result of asking for camera access.
nonisolated enum CameraPermission: Sendable {
    case granted
    case denied       // user said no -> can fix in Settings
    case restricted   // blocked by Screen Time / device management → user can't fix it
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
    func requestPermission() async -> CameraPermission
    func configure() async throws
    func start() async
    func stop() async
    /// Takes a photo. `onShutter` runs (any thread) at the moment the photo is taken, before the
    /// file is processed: the UI flashes there. Returns once the file is ready.
    func capturePhoto(onShutter: @escaping @Sendable () -> Void) async throws -> CapturedPhoto
    func personDetections() -> AsyncStream<PersonDetection?>
    func environmentUpdates() -> AsyncStream<LiveEnvironmentSignal?>
    func zoomUpdates() -> AsyncStream<Double?>
    /// Turns the body outline (old-look guide mode) on or off.
    func setOutlineEnabled(_ enabled: Bool)
    /// Take photos at the camera's largest size (mode F crops them).
    func setHighResolution(_ enabled: Bool)
    /// Current video zoom factor, or nil when the camera is not configured.
    var currentZoom: Double? { get }
    /// Smallest zoom factor the active format supports, or nil when unavailable.
    var minAvailableZoom: Double? { get }
    /// Largest zoom factor the active format supports, or nil when unavailable.
    var maxAvailableZoom: Double? { get }
    /// Requests a zoom factor, clamped to device limits and GoPhoto's automatic zoom cap.
    /// Returns the actual applied factor.
    func applyZoom(_ factor: Double) async -> Double
}

// MARK: - Real implementation

nonisolated final class CameraService: NSObject, CameraServiceProtocol, @unchecked Sendable {

    let session = AVCaptureSession()

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "gophoto.camera.session")
    private var isConfigured = false
    /// Photos being taken (session queue), by `AVCapturePhotoSettings.uniqueID`. Responsive
    /// capture lets a new shot start while the previous one is still processing.
    private var photoContinuations: [Int64: CheckedContinuation<CapturedPhoto, Error>] = [:]
    private var shutterCallbacks: [Int64: @Sendable () -> Void] = [:]
    
    // for the apple vision framework
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "gophoto.camera.video")
    private let personDetector = PersonDetector()
    private var personContinuation: AsyncStream<PersonDetection?>.Continuation?
    private var environmentContinuation: AsyncStream<LiveEnvironmentSignal?>.Continuation?
    private var zoomContinuation: AsyncStream<Double?>.Continuation?
    private let liveEnvironmentAnalyzer = LiveEnvironmentAnalyzer()
    private var environmentInferenceInFlight = false
    private var lastEnvironmentInferenceTime: TimeInterval = 0
    private var lastEnvironmentErrorLogTime: TimeInterval = 0
    private var frameCount = 0
    /// True from the shutter until the photo arrives (videoQueue): person detection pauses so the
    /// camera's photo pipeline gets the processor. The guide keeps its last values meanwhile.
    private var photosInFlight = 0
    private var isTakingPhoto: Bool { photosInFlight > 0 }
    /// Vertical field of view of the upright (portrait) frame, degrees. Set in `configureSession`.
    private var verticalFOV: Double?
    /// Largest photo size, megapixels (video queue copy for the guide).
    private var photoMegapixels: Double?
    /// Photo sizes (session queue): largest, and the one closest to 12 MP for normal shots.
    private var largestPhotoDimensions: CMVideoDimensions?
    private var normalPhotoDimensions: CMVideoDimensions?
    private var highResolution = false
    /// The camera (session queue), for the exposure and focus points.
    private var device: AVCaptureDevice?
    /// Current zoom factor on the active device.
    private var _currentZoom: Double = 1.0
    /// Supported zoom range for the active format.
    private var _minAvailableZoom: Double = 1.0
    private var _maxAvailableZoom: Double = 1.0
    /// Where exposure and focus last aimed (video queue), upright frame, origin top-left;
    /// nil = the camera's default (frame centre).
    private var meteringPoint: CGPoint?
    private var meteringUpdatedAt: TimeInterval = 0
    /// Re-aim only when the subject moved this far (frame fraction), at most this often, so the
    /// brightness doesn't pump as the face box jitters.
    private static let meteringMinMove: CGFloat = 0.05
    private static let meteringMinInterval: TimeInterval = 0.5                                                      

    // 1. Ask the user for camera permission (shows the iOS popup the first time)
    func requestPermission() async -> CameraPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    return .granted
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        case .restricted:    return .restricted
        default:             return .denied
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
                self.zoomContinuation?.yield(self.device == nil ? nil : self._currentZoom)
                continuation.resume()
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                if self.session.isRunning { self.session.stopRunning() }
                self.zoomContinuation?.yield(nil)
                continuation.resume()
            }
        }
    }

    // 4. Take a photo. The delegate callback below finishes this.
    func capturePhoto(onShutter: @escaping @Sendable () -> Void) async throws -> CapturedPhoto {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                // Portrait photo
                if let connection = self.photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                let settings = AVCapturePhotoSettings()
                if let dimensions = self.highResolution ? self.largestPhotoDimensions : self.normalPhotoDimensions {
                    settings.maxPhotoDimensions = dimensions
                }
                // Quality prioritization (benchmark): .quality = most multi-frame processing,
                // slowest file. .balanced is Apple's default; .speed the fastest.
                settings.photoQualityPrioritization = .quality
                self.photoContinuations[settings.uniqueID] = continuation
                self.shutterCallbacks[settings.uniqueID] = onShutter
                self.videoQueue.async { self.photosInFlight += 1 }
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
    
    func setHighResolution(_ enabled: Bool) {
        sessionQueue.async { self.highResolution = enabled }
    }

    func setOutlineEnabled(_ enabled: Bool) {
        videoQueue.async { self.personDetector.includeOutline = enabled }
    }

    // MARK: - Zoom control

    var currentZoom: Double? {
        sessionQueue.sync { device == nil ? nil : _currentZoom }
    }

    var minAvailableZoom: Double? {
        sessionQueue.sync { device == nil ? nil : _minAvailableZoom }
    }

    var maxAvailableZoom: Double? {
        sessionQueue.sync { device == nil ? nil : _maxAvailableZoom }
    }

    func zoomUpdates() -> AsyncStream<Double?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            sessionQueue.async {
                self.zoomContinuation = continuation
                continuation.yield(self.device == nil ? nil : self._currentZoom)
            }
            continuation.onTermination = { _ in
                self.sessionQueue.async { self.zoomContinuation = nil }
            }
        }
    }

    func applyZoom(_ factor: Double) async -> Double {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard let device = self.device else {
                    continuation.resume(returning: self._currentZoom)
                    return
                }
                let automaticMaximum = min(self._maxAvailableZoom, AdaptiveFOV.maximumAutomaticZoom)
                guard self._minAvailableZoom <= automaticMaximum else {
                    continuation.resume(returning: self._currentZoom)
                    return
                }
                let clamped = max(self._minAvailableZoom, min(automaticMaximum, factor))
                do {
                    try device.lockForConfiguration()
                    defer { device.unlockForConfiguration() }
                    device.videoZoomFactor = clamped
                    self._currentZoom = Double(device.videoZoomFactor)
                    self.zoomContinuation?.yield(self._currentZoom)
                } catch {
                    NSLog("GoPhoto camera zoom could not be applied: %@", error.localizedDescription)
                }
                continuation.resume(returning: self._currentZoom)
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

    func environmentUpdates() -> AsyncStream<LiveEnvironmentSignal?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            videoQueue.async { self.environmentContinuation = continuation }
            continuation.onTermination = { _ in
                self.videoQueue.async { self.environmentContinuation = nil }
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
        self.device = device
        _minAvailableZoom = device.minAvailableVideoZoomFactor
        _maxAvailableZoom = device.maxAvailableVideoZoomFactor
        _currentZoom = Double(device.videoZoomFactor)
        zoomContinuation?.yield(_currentZoom)
        // videoFieldOfView is across the sensor's long side, which is the height of a portrait frame.
        let fov = Double(device.activeFormat.videoFieldOfView)
        videoQueue.async { self.verticalFOV = fov > 0 ? fov : nil }
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)

        // Allow up to .quality per shot (the default ceiling is .balanced).
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Faster shutter: take the frame from the moment of the tap (zero shutter lag) and let
        // the next shot start while the previous one is still processing (responsive capture).
        if photoOutput.isZeroShutterLagSupported { photoOutput.isZeroShutterLagEnabled = true }
        if photoOutput.isResponsiveCaptureSupported {
            photoOutput.isResponsiveCaptureEnabled = true
            if photoOutput.isFastCapturePrioritizationSupported {
                photoOutput.isFastCapturePrioritizationEnabled = true
            }
        }

        // Allow the largest photo (mode F crops it); normal shots stay near 12 MP.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        func pixels(_ d: CMVideoDimensions) -> Int { Int(d.width) * Int(d.height) }
        if let largest = sizes.max(by: { pixels($0) < pixels($1) }) {
            photoOutput.maxPhotoDimensions = largest
            largestPhotoDimensions = largest
            normalPhotoDimensions = sizes.min(by: { abs(pixels($0) - 12_000_000) < abs(pixels($1) - 12_000_000) })
            let megapixels = Double(pixels(largest)) / 1_000_000
            videoQueue.async { self.photoMegapixels = megapixels }
        }
        
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
    /// The moment the photo is taken (shutter sound): tell the UI before the file is processed.
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        let id = resolvedSettings.uniqueID
        sessionQueue.async {
            self.shutterCallbacks.removeValue(forKey: id)?()
        }
    }

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

        let id = photo.resolvedSettings.uniqueID
        videoQueue.async { self.photosInFlight = max(0, self.photosInFlight - 1) }
        sessionQueue.async {
            self.shutterCallbacks.removeValue(forKey: id)?()        // in case it was never called
            self.photoContinuations.removeValue(forKey: id)?.resume(with: result)
        }
    }
}

// MARK: - Video frame delegate (called ~30x/sec on videoQueue)

nonisolated extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let continuation = personContinuation, !isTakingPhoto else { return }

        frameCount += 1
        guard frameCount.isMultiple(of: 2),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        scheduleEnvironmentAnalysis(from: pixelBuffer)
        var detection = personDetector.detect(in: pixelBuffer)
        detection?.verticalFOV = verticalFOV
        detection?.photoMegapixels = photoMegapixels
        continuation.yield(detection)
        updateMetering(for: detection)
    }

    /// Runs semantic scene analysis no more than once per second and never concurrently.
    private func scheduleEnvironmentAnalysis(from pixelBuffer: CVPixelBuffer) {
        guard environmentContinuation != nil, !environmentInferenceInFlight else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastEnvironmentInferenceTime >= 1 else { return }
        lastEnvironmentInferenceTime = now
        environmentInferenceInFlight = true
        guard let image = FrameDownscaler.cgImage(from: pixelBuffer, longEdge: 640) else {
            environmentInferenceInFlight = false
            environmentContinuation?.yield(nil)
            return
        }
        let analyzer = liveEnvironmentAnalyzer
        Task {
            do {
                let signal = try await analyzer.analyze(image, sampledAt: now)
                self.videoQueue.async {
                    self.environmentContinuation?.yield(signal)
                    self.environmentInferenceInFlight = false
                }
            } catch {
                self.videoQueue.async {
                    if now - self.lastEnvironmentErrorLogTime >= 30 {
                        NSLog("GoPhoto live environment analysis failed: %@", error.localizedDescription)
                        self.lastEnvironmentErrorLogTime = now
                    }
                    self.environmentContinuation?.yield(nil)
                    self.environmentInferenceInFlight = false
                }
            }
        }
    }

    /// Aims exposure and focus at the subject's face (else the top of the person's box, where
    /// the head is), so a bright sky behind them doesn't darken the face. Back to the frame
    /// centre when nobody is found. Video queue; not called while a photo is being taken.
    private func updateMetering(for detection: PersonDetection?) {
        let target: CGPoint? = detection.map { d in
            if let face = d.face { return CGPoint(x: face.midX, y: face.midY) }
            return CGPoint(x: d.box.midX, y: d.box.minY + d.box.height * 0.08)
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - meteringUpdatedAt >= Self.meteringMinInterval else { return }
        switch (target, meteringPoint) {
        case (nil, nil):
            return
        case let (new?, old?) where hypot(new.x - old.x, new.y - old.y) < Self.meteringMinMove:
            return
        default:
            break
        }
        meteringPoint = target
        meteringUpdatedAt = now
        // Upright portrait frame (top-left origin) → the sensor's landscape space: (y, 1 − x).
        let devicePoint = target.map { CGPoint(x: min(max($0.y, 0), 1), y: min(max(1 - $0.x, 0), 1)) }
            ?? CGPoint(x: 0.5, y: 0.5)
        sessionQueue.async { self.aim(at: devicePoint) }
    }

    /// Sets the exposure and focus point (sensor space), keeping both on continuous auto.
    /// Session queue.
    private func aim(at point: CGPoint) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure      // applies the new point
            }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .continuousAutoFocus
            }
        } catch {
            // Another client holds the configuration: keep the camera's own metering this time.
        }
    }
}
