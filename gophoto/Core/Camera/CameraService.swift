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
    /// Turns the body outline (old-look guide mode) on or off.
    func setOutlineEnabled(_ enabled: Bool)
    /// Take photos at the camera's largest size (mode F crops them).
    func setHighResolution(_ enabled: Bool)

    // MARK: - Lens recommendation support

    /// Current zoom capability of the active capture device.
    func lensCapabilities() -> LensCapabilities
    /// Apply a new zoom factor, clamped to the device's supported range.
    func applyZoom(_ factor: Double) -> Double
    /// Latest exposure snapshot, or nil if unavailable.
    func exposureSnapshot() -> ExposureSnapshot?
    /// Active physical constituent device type, when exposed by the OS.
    func activeConstituentDeviceType() -> AVCaptureDevice.DeviceType?

    // MARK: - Scene sampling (automatic lens switch)

    /// While enabled, a DETR class map of the live frame is taken about once a second (never every
    /// frame) and kept for `latestSceneSample()`. Disabling clears the stored sample.
    func setSceneSampling(_ enabled: Bool)
    /// The newest class map with its person box and zoom, or nil.
    func latestSceneSample() -> SceneSample?
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
    private var frameCount = 0
    // Scene sampling for the automatic lens switch (DETR class map, on demand).
    private let segmenter = DETRSegmenter()
    private static let sceneSampleInterval: TimeInterval = 1.0
    private var sceneSamplingEnabled = false      // video queue
    private var sceneSampleInFlight = false       // video queue
    private var lastSceneSampleAt: TimeInterval = 0   // video queue
    private let sceneSampleLock = NSLock()
    private var sceneSample: SceneSample?         // guarded by sceneSampleLock
    /// True from the shutter until the photo arrives (videoQueue): person detection pauses so the
    /// camera's photo pipeline gets the processor. The guide keeps its last values meanwhile.
    private var photosInFlight = 0
    private var isTakingPhoto: Bool { photosInFlight > 0 }
    /// Vertical field of view of the upright (portrait) frame, degrees. Set in `configureSession`.
    private var verticalFOV: Double?
    /// Vertical field of view of the active format at device zoom 1.0 before any digital zoom,
    /// degrees. Exposed so the zoom controller can convert between angular and frame-fraction
    /// measures without depending on the camera service.
    private(set) var baseVerticalFOV: Double? {
        get { _baseVerticalFOV }
        set { _baseVerticalFOV = newValue }
    }
    private var _baseVerticalFOV: Double?
    /// Largest photo size, megapixels (video queue copy for the guide).
    private var photoMegapixels: Double?
    /// Photo sizes (session queue): largest, and the one closest to 12 MP for normal shots.
    private var largestPhotoDimensions: CMVideoDimensions?
    private var normalPhotoDimensions: CMVideoDimensions?
    private var highResolution = false
    /// The camera (session queue), for the exposure and focus points.
    private var device: AVCaptureDevice?
    /// Where exposure and focus last aimed (video queue), upright frame, origin top-left;
    /// nil = the camera's default (frame centre).
    private var meteringPoint: CGPoint?
    private var meteringUpdatedAt: TimeInterval = 0
    /// Re-aim only when the subject moved this far (frame fraction), at most this often, so the
    /// brightness doesn't pump as the face box jitters.
    private static let meteringMinMove: CGFloat = 0.05
    private static let meteringMinInterval: TimeInterval = 0.5
    /// Mapping between user-perceived zoom (0.5×, 1×, 2×...) and the device's raw
    /// `videoZoomFactor`. On virtual multi-camera devices the device reports zoom
    /// relative to the active constituent lens, so we derive a linear scale from the
    /// first virtual switch-over breakpoint.
    private struct ZoomMapping {
        let deviceMin: Double
        let deviceMax: Double
        let userMin: Double
        let userMax: Double
        let firstBreakpoint: Double?

        func userZoom(from deviceZoom: Double) -> Double {
            guard let first = firstBreakpoint, first > 0 else { return deviceZoom }
            return deviceZoom / first
        }

        func deviceZoom(for userZoom: Double) -> Double {
            guard let first = firstBreakpoint, first > 0 else { return userZoom }
            return userZoom * first
        }
    }
    private var zoomMapping: ZoomMapping = .init(
        deviceMin: 1, deviceMax: 1, userMin: 1, userMax: 1, firstBreakpoint: nil
    )
    /// User-perceived zoom the app last applied. Used as the single source of truth
    /// for UI labels, preset highlighting, and Lens Recommendation comparisons.
    private var currentUserZoom: Double = 1.0
    /// The startup zoom has to be re-checked once after the first `startRunning` (session queue).
    private var initialZoomPending = false

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
                    let firstTime = !self.isConfigured
                    try self.configureSession()      // committed when this returns
                    if firstTime {
                        self.applyInitialZoom()
                        self.initialZoomPending = true
                    }
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
                // First start only: if starting the session reset the zoom, restore 1×. Later
                // restarts keep whatever zoom the user or the auto switch chose.
                if self.initialZoomPending {
                    self.initialZoomPending = false
                    self.applyInitialZoom()
                }
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

    // MARK: - Lens recommendation support

    func lensCapabilities() -> LensCapabilities {
        guard let device else { return LensCapabilities(minZoom: 1, maxZoom: 1, currentZoom: 1, deviceType: .builtInWideAngleCamera, opticalBreakpoints: []) }
        // Read the zoom the device really has, so the label can never drift from the preview.
        currentUserZoom = zoomMapping.userZoom(from: device.videoZoomFactor)
        return LensCapabilities.from(
            device,
            currentUserZoom: currentUserZoom,
            userMin: zoomMapping.userMin,
            userMax: zoomMapping.userMax
        )
    }

    /// Select the best back camera for the current hardware.
    ///
    /// Prefer virtual multi-camera devices (dual-wide, triple) because they expose a wider
    /// zoom range that includes genuine ultrawide coverage (e.g. 0.5×). Fall back to the
    /// physical wide-angle camera when no virtual multi-camera is available.
    ///
    /// This is a startup-time selection. The session is not reconfigured after this point,
    /// so the choice must reflect the device's actual capabilities rather than a hardcoded
    /// assumption that every iPhone supports 0.5×.
    private func discoverBestBackCamera() -> AVCaptureDevice? {
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInDualWideCamera,   // virtual: ultrawide + wide
            .builtInTripleCamera,     // virtual: ultrawide + wide + telephoto
            .builtInWideAngleCamera,  // physical wide, or virtual on some devices
        ]
        for type in preferredTypes {
            if let device = AVCaptureDevice.default(type, for: .video, position: .back) {
                return device
            }
        }
        return nil
    }

    /// Builds the user-perceived zoom mapping from the device's actual zoom range. Must run once the
    /// input is in the session and committed: the range depends on the session's active format.
    private func refreshZoomMapping(for device: AVCaptureDevice) {
        let breakpoints = (device.virtualDeviceSwitchOverVideoZoomFactors as? [Double]) ?? []
        let deviceMin = device.minAvailableVideoZoomFactor
        let deviceMax = device.maxAvailableVideoZoomFactor
        let userMin: Double
        let userMax: Double
        let first: Double?
        if let bp = breakpoints.first, bp > 0 {
            first = bp
            // Virtual multi-camera: device zoom is scaled by the first breakpoint.
            // The user-perceived range spans from the widest view the device can deliver
            // (normally 0.5×) up to the device ceiling, capped at 3.0× for this feature.
            userMin = max(0.5, deviceMin / bp)
            userMax = min(3.0, deviceMax / bp)
        } else {
            first = nil
            // Physical camera or unknown virtual: 1:1 mapping, capped at 3.0×.
            userMin = max(0.5, deviceMin)
            userMax = min(3.0, deviceMax)
        }
        zoomMapping = ZoomMapping(deviceMin: deviceMin, deviceMax: deviceMax,
                                  userMin: userMin, userMax: userMax, firstBreakpoint: first)
    }

    /// Puts the camera at 1× (the standard wide view) and syncs the zoom state and field of view to
    /// what the device really reports. Session queue; runs after the session configuration is
    /// committed, and again once after the session starts running.
    private func applyInitialZoom() {
        guard let device else { return }
        refreshZoomMapping(for: device)
        let target = max(zoomMapping.deviceMin, min(zoomMapping.deviceMax, zoomMapping.deviceZoom(for: 1.0)))
        if abs(device.videoZoomFactor - target) > 0.001 {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = target
                device.unlockForConfiguration()
            } catch {
                LensRecommendationLog.error("initial_zoom_failed: lock_failed")
            }
        }
        // Report the zoom the device actually has, never the one that was asked for.
        currentUserZoom = zoomMapping.userZoom(from: device.videoZoomFactor)
        // `videoFieldOfView` is the format's full view (zoom 1.0), across the sensor's long side =
        // the height of a portrait frame.
        let fov = Double(device.activeFormat.videoFieldOfView)
        baseVerticalFOV = fov > 0 ? fov : nil
        updateFieldOfView(deviceZoom: device.videoZoomFactor)
    }

    func applyZoom(_ userFactor: Double) -> Double {
        guard let device else {
            LensRecommendationLog.error("apply_zoom_failed: no_device")
            return 1
        }
        let targetDeviceZoom = zoomMapping.deviceZoom(for: userFactor)
        let clamped = max(zoomMapping.deviceMin, min(zoomMapping.deviceMax, targetDeviceZoom))
        // Already there: don't lock/reconfigure the camera again.
        guard abs(device.videoZoomFactor - clamped) > 0.001 else { return currentUserZoom }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            LensRecommendationLog.error("apply_zoom_failed: lock_failed")
            return currentUserZoom
        }
        currentUserZoom = zoomMapping.userZoom(from: clamped)
        updateFieldOfView(deviceZoom: clamped)
        return currentUserZoom
    }

    /// Keeps the vertical field of view the guide reads in step with the zoom: the format's full view
    /// is at device zoom 1.0, and a larger zoom narrows it.
    private func updateFieldOfView(deviceZoom: Double) {
        guard let base = baseVerticalFOV, base > 0, deviceZoom > 0 else { return }
        let fov = 2 * atan(tan(base * .pi / 360) / deviceZoom) * 180 / .pi
        videoQueue.async { self.verticalFOV = fov }
    }

    func exposureSnapshot() -> ExposureSnapshot? {
        guard let device else {
            LensRecommendationLog.error("exposure_unavailable: no_device")
            return nil
        }
        let iso = device.iso
        let duration = device.exposureDuration.seconds
        let offset = device.exposureTargetOffset
        guard iso > 0, duration > 0 else {
            LensRecommendationLog.error("exposure_unavailable: iso_or_duration_zero")
            return nil
        }
        return ExposureSnapshot(
            iso: Float(iso),
            exposureDuration: duration,
            exposureTargetOffset: offset
        )
    }

    // MARK: - Scene sampling

    func setSceneSampling(_ enabled: Bool) {
        videoQueue.async {
            self.sceneSamplingEnabled = enabled
            if !enabled {
                self.sceneSampleLock.withLock { self.sceneSample = nil }
            }
        }
    }

    func latestSceneSample() -> SceneSample? {
        sceneSampleLock.withLock { sceneSample }
    }

    /// Video queue. At most one DETR run at a time and one per `sceneSampleInterval`, only while
    /// someone asked for samples and a person is in the frame. The frame is copied to a small
    /// CGImage first so the capture buffer is released at once.
    private func sampleSceneIfNeeded(_ pixelBuffer: CVPixelBuffer, person: PersonDetection?) {
        guard sceneSamplingEnabled, !sceneSampleInFlight, let box = person?.box else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastSceneSampleAt >= Self.sceneSampleInterval,
              let image = FrameDownscaler.cgImage(from: pixelBuffer, longEdge: 512) else { return }
        sceneSampleInFlight = true
        lastSceneSampleAt = now
        let zoom = currentUserZoom
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let map: SegmentationMap?
            do { map = try await self.segmenter.segment(image) } catch {
                LensRecommendationLog.error("scene_sample_failed: \(error.localizedDescription)")
                map = nil
            }
            self.videoQueue.async {
                self.sceneSampleInFlight = false
                // Dropped when sampling was switched off, or the zoom changed while the model ran.
                guard self.sceneSamplingEnabled, let map, abs(self.currentUserZoom - zoom) < 0.02 else { return }
                let sample = SceneSample(map: map, subjectBox: box, zoom: zoom,
                                         capturedAt: ProcessInfo.processInfo.systemUptime)
                self.sceneSampleLock.withLock { self.sceneSample = sample }
            }
        }
    }

    func activeConstituentDeviceType() -> AVCaptureDevice.DeviceType? {
        guard let device else { return nil }
        if #available(iOS 15.0, *) {
            return device.activePrimaryConstituent?.deviceType
        }
        return nil
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

        guard let device = discoverBestBackCamera() else {
            throw CameraError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        self.device = device

        // The zoom range, the 1× zoom and the field of view are NOT set here. Adding the input to the
        // session applies the session's format and resets `videoZoomFactor` to 1.0, which on a virtual
        // multi-camera is the 0.5× ultra wide view. They are set after the configuration is committed
        // (`applyInitialZoom`).
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

        var detection = personDetector.detect(in: pixelBuffer)
        detection?.verticalFOV = verticalFOV
        detection?.photoMegapixels = photoMegapixels
        continuation.yield(detection)
        sampleSceneIfNeeded(pixelBuffer, person: detection)
        updateMetering(for: detection)
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
