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

/// Whether live native depth can run (Phased + Depth), and why not.
nonisolated struct LiveDepthSupport: Sendable, Equatable {
    var available: Bool
    /// The reason when not available; the depth format / accuracy when it is.
    var note: String
}

/// Depth on the subject from one depth frame (Phased + Depth).
typealias LiveDepthFrame = DepthSample

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

/// The light the camera sees now: the backlight tip, plus values for the debug panel.
nonisolated struct ExposureStatus: Sendable, Equatable {
    /// Where to move because the person is backlit; nil when they are not.
    let backlightTip: BacklightTip?
    /// ISO, and shutter time in seconds (auto-exposure, never changed by the app).
    let iso: Float
    let shutter: Double
    /// The backlight rule currently sees a backlit person (the tip follows after a moment).
    let isBacklit: Bool
    /// How bright the face (nil: none found), the whole frame and the background left / right of
    /// the person are, 0...1.
    let faceLuminance: Double?
    let frameLuminance: Double
    /// The brightest area behind the person (a window, the sky).
    let peakLuminance: Double
    let leftLuminance: Double?
    let rightLuminance: Double?
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
    /// Developer blur (temporary): switch to the dual / triple camera so photos carry Apple's
    /// depth + portrait matte (true), or back to the main camera (false). Returns whether depth
    /// capture is on now (false when the phone has no depth camera).
    func setDepthCapture(_ enabled: Bool) async -> Bool

    // Phased guide (appMode 2 experiment)
    /// Strict subject lock: the detector never picks a person on its own (see `PersonDetector.strictLock`).
    func setStrictSubjectLock(_ enabled: Bool)
    /// Dim everything but people in the detections (`PersonDetection.dimMask`), for choosing a person.
    func setSelectionDimming(_ enabled: Bool)
    /// Follow the person in `box` (normalized, origin top-left) from the next frame on.
    func lockSubject(to box: CGRect)
    /// Zoom factors (app units) that use the lens / a sensor crop rather than digital zoom, e.g. [2]
    /// on a 48 MP main camera. Empty when the format reports none.
    var nativeZoomFactors: [Double] { get }
    /// Phased + Depth: stream native depth with the video (needs the dual / triple camera, see
    /// `setDepthCapture`). Returns what is available now.
    func setLiveDepth(_ enabled: Bool) async -> LiveDepthSupport
    /// Depth on the subject for each depth frame while live depth is on.
    func depthUpdates() -> AsyncStream<LiveDepthFrame>
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
    // Phased + Depth: live depth next to the video (dual / triple camera only).
    private let depthOutput = AVCaptureDepthDataOutput()
    private var liveDepthOn = false                   // session queue
    private var depthContinuation: AsyncStream<LiveDepthFrame>.Continuation?   // video queue
    /// The locked subject's box (video queue) where the depth is sampled.
    private var depthSubjectBox: CGRect?
    /// Depth frames are rotated upright by their connection (else mapped from the sensor's landscape).
    private var depthUpright = false
    private var depthFrameCount = 0
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
    /// Vertical field of view of the upright (portrait) frame at zoom 1, degrees. Set in
    /// `configureSession`. Each frame's field of view is narrowed by the zoom at that moment.
    private var verticalFOV: Double?
    /// The camera, for the video queue: each frame reads the zoom it was taken with.
    private var videoDevice: AVCaptureDevice?
    /// How fast automatic zoom moves, in powers of two per second (1 = doubles in a second).
    /// A ramp instead of a jump: the preview glides like the system camera.
    static let zoomRampRate: Float = 1.0

    /// Field of view after zooming by `zoom` (the zoom crops the sensor's centre).
    static func effectiveFOV(_ fov: Double, zoom: Double) -> Double {
        guard zoom > 0 else { return fov }
        return 2 * atan(tan(fov * .pi / 360) / zoom) * 180 / .pi
    }
    /// Largest photo size, megapixels (video queue copy for the guide).
    private var photoMegapixels: Double?
    /// Photo sizes (session queue): largest, and the one closest to 12 MP for normal shots.
    private var largestPhotoDimensions: CMVideoDimensions?
    private var normalPhotoDimensions: CMVideoDimensions?
    private var highResolution = false
    /// The camera (session queue), for the exposure and focus points.
    private var device: AVCaptureDevice?
    /// Device zoom factor that the app calls 1×. 1 on the main camera; on a virtual (dual / triple)
    /// camera its factor 1 is the ultra wide, so 1× = the switch-over to the main lens. All zoom
    /// values the app sees are divided by it (session queue / video queue copies).
    private var zoomScale: Double = 1
    private var videoZoomScale: Double = 1
    /// Depth capture is on (session queue).
    private var depthActive = false
    /// Current zoom factor on the active device (app units, see `zoomScale`).
    private var _currentZoom: Double = 1.0
    /// Supported zoom range for the active format.
    private var _minAvailableZoom: Double = 1.0
    private var _maxAvailableZoom: Double = 1.0
    /// Copy of the zoom values for readers on other threads (the main actor reads them for every
    /// detection). Reading through `sessionQueue.sync` blocked the main thread for as long as the
    /// session queue was busy, e.g. the whole `stopRunning()` when the gallery opened.
    private struct ZoomSnapshot { var current, min, max: Double? }
    private let zoomLock = NSLock()
    private var zoomSnapshot = ZoomSnapshot()
    /// Lens / sensor-crop zoom factors of the active format, app units (under `zoomLock`).
    private var nativeZooms: [Double] = []
    /// Where exposure and focus last aimed (video queue), upright frame, origin top-left;
    /// nil = the camera's default (frame centre).
    private var meteringPoint: CGPoint?
    private var meteringUpdatedAt: TimeInterval = 0
    /// Re-aim only when the subject moved this far (frame fraction), at most this often, so the
    /// brightness doesn't pump as the face box jitters.
    private static let meteringMinMove: CGFloat = 0.05
    private static let meteringMinInterval: TimeInterval = 0.5

    // Backlight, on the video queue: the face is measured against the frame about twice a second,
    // and the controller answers with where to move. The camera's exposure is left alone.
    private let luminanceMeter = LuminanceMeter()
    private var backlight = BacklightController()
    private var luminanceMeasuredAt: TimeInterval = 0
    private var statusContinuation: AsyncStream<ExposureStatus>.Continuation?
    private static let luminanceInterval: TimeInterval = 0.5

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
                // Developer blur: Apple's depth + portrait matte, embedded in the file (the Photos
                // app can then treat it as a Portrait photo; GoPhoto renders the blur from it).
                if self.photoOutput.isDepthDataDeliveryEnabled {
                    settings.isDepthDataDeliveryEnabled = true
                    settings.embedsDepthDataInPhoto = true
                    if self.photoOutput.isPortraitEffectsMatteDeliveryEnabled {
                        settings.isPortraitEffectsMatteDeliveryEnabled = true
                        settings.embedsPortraitEffectsMatteInPhoto = true
                    }
                }
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

    func setStrictSubjectLock(_ enabled: Bool) {
        videoQueue.async { self.personDetector.strictLock = enabled }
    }

    func setSelectionDimming(_ enabled: Bool) {
        videoQueue.async { self.personDetector.wantsDimMask = enabled }
    }

    func lockSubject(to box: CGRect) {
        videoQueue.async { self.personDetector.lock(to: box) }
    }

    var nativeZoomFactors: [Double] { zoomLock.withLock { nativeZooms } }

    // MARK: - Zoom control

    // Non-blocking: read the snapshot, never wait for the session queue.
    var currentZoom: Double? { zoomLock.withLock { zoomSnapshot.current } }
    var minAvailableZoom: Double? { zoomLock.withLock { zoomSnapshot.min } }
    var maxAvailableZoom: Double? { zoomLock.withLock { zoomSnapshot.max } }

    /// Session queue: copies the zoom values for `currentZoom` / `min` / `max`.
    private func publishZoomSnapshot() {
        let snapshot = device == nil
            ? ZoomSnapshot()
            : ZoomSnapshot(current: _currentZoom, min: _minAvailableZoom, max: _maxAvailableZoom)
        zoomLock.withLock { zoomSnapshot = snapshot }
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
                    // Glide to the target (a jump made the preview twitch). The frames report
                    // the zoom they were taken with while the ramp runs.
                    device.ramp(toVideoZoomFactor: CGFloat(clamped * self.zoomScale), withRate: Self.zoomRampRate)
                    self._currentZoom = Double(clamped)   // target; the frames publish the live value
                    self.zoomContinuation?.yield(Double(clamped))
                } catch {
                    NSLog("GoPhoto camera zoom could not be applied: %@", error.localizedDescription)
                }
                continuation.resume(returning: Double(clamped))
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
        try attach(device)

        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)
        configurePhotoOutput(for: device, depth: false)

        // live video frames → person detection
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)
        rotateVideoFrames()

        isConfigured = true
    }

    /// Session queue, inside a configuration: connects `device` as the camera and resets the zoom
    /// to the app's 1× (the main lens; on a virtual camera its switch-over factor).
    private func attach(_ device: AVCaptureDevice) throws {
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        self.device = device
        let scale = device.isVirtualDevice
            ? (device.virtualDeviceSwitchOverVideoZoomFactors.first.map { Double(truncating: $0) } ?? 1)
            : 1
        zoomScale = scale
        // Never below the main lens (the guide and the zoom logic assume it).
        _minAvailableZoom = max(1, Double(device.minAvailableVideoZoomFactor) / scale)
        _maxAvailableZoom = Double(device.maxAvailableVideoZoomFactor) / scale
        // Every session starts at the baseline. The device object is shared, so it still has the
        // zoom the previous session left it at.
        let baseline = max(_minAvailableZoom, min(_maxAvailableZoom, AdaptiveFOV.baselineZoom))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = CGFloat(baseline * scale)
            device.unlockForConfiguration()
        } catch {
            NSLog("GoPhoto camera zoom could not be reset: %@", error.localizedDescription)
        }
        _currentZoom = Double(device.videoZoomFactor) / scale
        let native = device.activeFormat.secondaryNativeResolutionZoomFactors.map { Double($0) / scale }
        zoomLock.withLock { nativeZooms = native }
        publishZoomSnapshot()
        zoomContinuation?.yield(_currentZoom)
        // videoFieldOfView is across the sensor's long side, which is the height of a portrait
        // frame, at the device's zoom factor 1 (each frame narrows it by the device zoom).
        let fov = Double(device.activeFormat.videoFieldOfView)
        // AVCaptureDevice is thread-safe to read; the video queue only reads its zoom.
        nonisolated(unsafe) let zoomDevice = device
        videoQueue.async {
            self.verticalFOV = fov > 0 ? fov : nil
            self.videoDevice = zoomDevice
            self.videoZoomScale = scale
        }
    }

    /// Upright live frames, same as the photo.
    private func rotateVideoFrames() {
        if let connection = videoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    /// Session queue, inside a configuration: photo settings for `device` (depth first: zero
    /// shutter lag and responsive capture depend on it).
    private func configurePhotoOutput(for device: AVCaptureDevice, depth: Bool) {
        photoOutput.isPortraitEffectsMatteDeliveryEnabled = false
        photoOutput.isDepthDataDeliveryEnabled = depth && photoOutput.isDepthDataDeliverySupported
        if photoOutput.isDepthDataDeliveryEnabled {
            photoOutput.isPortraitEffectsMatteDeliveryEnabled = photoOutput.isPortraitEffectsMatteDeliverySupported
        }

        // Allow up to .quality per shot (the default ceiling is .balanced).
        photoOutput.maxPhotoQualityPrioritization = .quality

        // Faster shutter: take the frame from the moment of the tap (zero shutter lag) and let
        // the next shot start while the previous one is still processing (responsive capture).
        // (Set every time: depth capture can take these away, turning it off gives them back.)
        photoOutput.isZeroShutterLagEnabled = photoOutput.isZeroShutterLagSupported
        photoOutput.isResponsiveCaptureEnabled = photoOutput.isResponsiveCaptureSupported
        photoOutput.isFastCapturePrioritizationEnabled = photoOutput.isResponsiveCaptureEnabled
            && photoOutput.isFastCapturePrioritizationSupported

        // Crop-guide modes capture at the largest supported dimensions; saved framing stays untouched.
        let sizes = device.activeFormat.supportedMaxPhotoDimensions
        func pixels(_ d: CMVideoDimensions) -> Int { Int(d.width) * Int(d.height) }
        if var largest = sizes.max(by: { pixels($0) < pixels($1) }) {
            // Depth photos: stay at about 12 MP (depth and the matte are made for that size).
            if photoOutput.isDepthDataDeliveryEnabled,
               let normal = sizes.min(by: { abs(pixels($0) - 12_000_000) < abs(pixels($1) - 12_000_000) }) {
                largest = normal
            }
            photoOutput.maxPhotoDimensions = largest
            largestPhotoDimensions = largest
            normalPhotoDimensions = sizes.min(by: { abs(pixels($0) - 12_000_000) < abs(pixels($1) - 12_000_000) })
            let megapixels = Double(pixels(largest)) / 1_000_000
            videoQueue.async { self.photoMegapixels = megapixels }
        }
    }

    func setDepthCapture(_ enabled: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard self.isConfigured else { continuation.resume(returning: false); return }
                guard enabled != self.depthActive else { continuation.resume(returning: self.depthActive); return }
                // The main camera has no depth: live depth stops before switching back to it.
                if !enabled, self.liveDepthOn { self.removeLiveDepth() }
                let target: AVCaptureDevice? = enabled
                    ? [AVCaptureDevice.DeviceType.builtInDualWideCamera, .builtInDualCamera, .builtInTripleCamera]
                        .lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }.first
                    : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                guard let target else { continuation.resume(returning: false); return }
                let previous = self.device
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                do {
                    try self.attach(target)
                } catch {
                    if let previous { try? self.attach(previous) }   // keep a working camera
                }
                self.configurePhotoOutput(for: self.device ?? target, depth: enabled)
                self.rotateVideoFrames()
                self.session.commitConfiguration()
                self.depthActive = enabled && self.photoOutput.isDepthDataDeliveryEnabled
                continuation.resume(returning: self.depthActive)
            }
        }
    }

    // MARK: - Live depth (Phased + Depth)

    /// Whether this iPhone has a camera that streams native depth (checked without the session).
    static func liveDepthSupport() -> LiveDepthSupport {
        let types: [AVCaptureDevice.DeviceType] = [.builtInDualWideCamera, .builtInDualCamera, .builtInTripleCamera]
        guard let device = types.lazy.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first else {
            return LiveDepthSupport(available: false, note: "no dual camera on this iPhone")
        }
        guard device.formats.contains(where: { !$0.supportedDepthDataFormats.isEmpty }) else {
            return LiveDepthSupport(available: false, note: "\(device.localizedName) has no depth formats")
        }
        return LiveDepthSupport(available: true, note: device.localizedName)
    }

    func depthUpdates() -> AsyncStream<LiveDepthFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            videoQueue.async { self.depthContinuation = continuation }
            continuation.onTermination = { _ in
                self.videoQueue.async { self.depthContinuation = nil }
            }
        }
    }

    func setLiveDepth(_ enabled: Bool) async -> LiveDepthSupport {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                guard self.isConfigured else {
                    continuation.resume(returning: LiveDepthSupport(available: false, note: "camera not ready")); return
                }
                guard enabled else {
                    if self.liveDepthOn { self.removeLiveDepth() }
                    continuation.resume(returning: LiveDepthSupport(available: false, note: "off")); return
                }
                guard self.depthActive, let device = self.device else {
                    continuation.resume(returning: LiveDepthSupport(available: false, note: "needs the dual camera")); return
                }
                if self.liveDepthOn {
                    continuation.resume(returning: LiveDepthSupport(available: true, note: self.depthFormatNote(device))); return
                }
                let wanted: [OSType] = [kCVPixelFormatType_DepthFloat16, kCVPixelFormatType_DepthFloat32,
                                        kCVPixelFormatType_DisparityFloat16, kCVPixelFormatType_DisparityFloat32]
                let formats = device.activeFormat.supportedDepthDataFormats.filter {
                    wanted.contains(CMFormatDescriptionGetMediaSubType($0.formatDescription))
                }
                guard let best = formats.max(by: {
                    CMVideoFormatDescriptionGetDimensions($0.formatDescription).width
                        < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
                }) else {
                    continuation.resume(returning: LiveDepthSupport(available: false, note: "no depth format for this photo format")); return
                }
                self.session.beginConfiguration()
                guard self.session.canAddOutput(self.depthOutput) else {
                    self.session.commitConfiguration()
                    continuation.resume(returning: LiveDepthSupport(available: false, note: "depth output cannot be added")); return
                }
                self.session.addOutput(self.depthOutput)
                self.depthOutput.isFilteringEnabled = false      // holes stay holes: counted as invalid
                self.depthOutput.alwaysDiscardsLateDepthData = true
                self.depthOutput.setDelegate(self, callbackQueue: self.videoQueue)
                do {
                    try device.lockForConfiguration()
                    device.activeDepthDataFormat = best
                    device.unlockForConfiguration()
                } catch {
                    NSLog("GoPhoto depth format could not be set: %@", error.localizedDescription)
                }
                var upright = false
                if let connection = self.depthOutput.connection(with: .depthData),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                    upright = true
                }
                self.session.commitConfiguration()
                self.liveDepthOn = true
                self.videoQueue.async { self.depthUpright = upright }
                continuation.resume(returning: LiveDepthSupport(available: true, note: self.depthFormatNote(device)))
            }
        }
    }

    /// Session queue, outside a configuration.
    private func removeLiveDepth() {
        session.beginConfiguration()
        if session.outputs.contains(depthOutput) { session.removeOutput(depthOutput) }
        session.commitConfiguration()
        liveDepthOn = false
    }

    private func depthFormatNote(_ device: AVCaptureDevice) -> String {
        guard let format = device.activeDepthDataFormat else { return "depth format unknown" }
        let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let type = CMFormatDescriptionGetMediaSubType(format.formatDescription)
        let kind = type == kCVPixelFormatType_DisparityFloat16 || type == kCVPixelFormatType_DisparityFloat32 ? "disparity" : "depth"
        return "\(device.localizedName) · \(kind) \(d.width)×\(d.height)"
    }
}

// MARK: - Depth delegate (Phased + Depth, video queue)

nonisolated extension CameraService: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData,
                         timestamp: CMTime, connection: AVCaptureConnection) {
        guard let continuation = depthContinuation, let box = depthSubjectBox else { return }
        depthFrameCount += 1
        guard depthFrameCount.isMultiple(of: 2) else { return }     // about 15 a second is enough
        let converted = depthData.depthDataType == kCVPixelFormatType_DepthFloat32
            ? depthData : depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let map = converted.depthDataMap
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        let w = CVPixelBufferGetWidth(map), h = CVPixelBufferGetHeight(map)
        let rowBytes = CVPixelBufferGetBytesPerRow(map)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(map) else { return }
        // Torso: inside the box, away from its edges (background) and the arms; a grid of points.
        var values: [Double] = []
        let grid = 10
        var total = 0
        for iy in 0..<grid {
            for ix in 0..<grid {
                let ux = Double(box.minX) + Double(box.width) * (0.32 + 0.36 * Double(ix) / Double(grid - 1))
                let uy = Double(box.minY) + Double(box.height) * (0.22 + 0.33 * Double(iy) / Double(grid - 1))
                // Upright (top-left) → buffer: rotated connection = same; else the sensor's landscape.
                let (px, py) = depthUpright ? (ux, uy) : (uy, 1 - ux)
                let x = Int(px * Double(w)), y = Int(py * Double(h))
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                total += 1
                let value = Double(base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)[x])
                if value.isFinite, value > 0 { values.append(value) }
            }
        }
        guard total > 0 else { return }
        values.sort()
        let median = values.isEmpty ? 0 : values[values.count / 2]
        continuation.yield(DepthSample(value: median, validFraction: Double(values.count) / Double(total),
                                       absolute: depthData.depthDataAccuracy == .absolute,
                                       sampleCount: values.count, time: ProcessInfo.processInfo.systemUptime))
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
        // The zoom this frame was taken with: the field of view narrows with it.
        // Device factor for the field of view; app units (÷ `videoZoomScale`) for everything else.
        let deviceZoom = videoDevice.map { Double($0.videoZoomFactor) }
        let zoom = deviceZoom.map { $0 / videoZoomScale }
        let ramping = videoDevice?.isRampingVideoZoom ?? false
        if let zoom { zoomLock.withLock { if zoomSnapshot.current != nil { zoomSnapshot.current = zoom } } }
        var detection = personDetector.detect(in: pixelBuffer)
        detection?.verticalFOV = verticalFOV.map { Self.effectiveFOV($0, zoom: deviceZoom ?? 1) }
        detection?.zoomFactor = zoom
        detection?.isZooming = ramping
        detection?.photoMegapixels = photoMegapixels
        // Strict lock without a subject: only candidates, no box to aim at or to sample depth on.
        let subject = detection?.subjectLocked == false ? nil : detection
        depthSubjectBox = subject.map { $0.extent ?? $0.box }
        continuation.yield(detection)
        updateMetering(for: subject)
        updateBacklight(face: subject?.face, person: subject?.box, pixelBuffer: pixelBuffer)
    }

    /// Backlight rule (video queue): measures the face against the frame, the brightest light behind
    /// the person and the background on each side of the person. Throttled.
    private func updateBacklight(face: CGRect?, person: CGRect?, pixelBuffer: CVPixelBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - luminanceMeasuredAt >= Self.luminanceInterval,
              let reading = luminanceMeter.measure(pixelBuffer, face: face, person: person) else { return }
        luminanceMeasuredAt = now
        let tip = backlight.update(faceLuminance: reading.face, frameLuminance: reading.frame,
                                   peakLuminance: reading.peak, leftLuminance: reading.left, rightLuminance: reading.right, now: now)
        let isBacklit = backlight.isBacklit
        sessionQueue.async {
            self.publishStatus(tip: tip, isBacklit: isBacklit, reading: reading)
        }
    }

    /// Session queue (where the camera is read).
    private func publishStatus(tip: BacklightTip?, isBacklit: Bool, reading: LuminanceMeter.Reading) {
        guard let device else { return }
        let status = ExposureStatus(backlightTip: tip, iso: device.iso,
                                    shutter: device.exposureDuration.seconds, isBacklit: isBacklit,
                                    faceLuminance: reading.face, frameLuminance: reading.frame,
                                    peakLuminance: reading.peak, leftLuminance: reading.left, rightLuminance: reading.right)
        videoQueue.async { self.statusContinuation?.yield(status) }
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
