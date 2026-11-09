//
//  ReplayCameraService.swift
//  gophoto
//
//  appMode 2 testing: the replay ADAPTER. It conforms to `CameraServiceProtocol`, so the ViewModel,
//  the production `PersonDetector` (its own instance), GuideFlow / TeamGuideFlow / PhasedEngine run
//  unchanged on video frames. It is also the action sink: zoom and capture never reach the camera.
//
//  Sensors a video does not carry stay missing: no field of view, no zoom changes (1, min = max = 1),
//  no depth, no motion (the ViewModel stops reading the phone's sensors in Replay).
//  Spec: Docs/Experiments/Replay/Spec.md.
//
import AVFoundation
import CoreImage
import UIKit

nonisolated enum ReplayError2: LocalizedError {
    case noCamera
    var errorDescription: String? { "Replay has no camera: use “Save test frame”." }
}

/// Counters for the run summary (analysis thread).
nonisolated struct ReplayPipelineStats: Sendable, Equatable {
    var shown = 0
    var analysed = 0
    /// Frames on the analysis stride that were skipped because the previous one was still running.
    var droppedBusy = 0
    var lagSum = 0.0
    var lagMax = 0.0
    var analysisSum = 0.0
    var lateFrames = 0
    var lagMean: Double { analysed > 0 ? lagSum / Double(analysed) : 0 }
    var analysisMean: Double { analysed > 0 ? analysisSum / Double(analysed) : 0 }
}

nonisolated final class ReplayCameraService: NSObject, CameraServiceProtocol, @unchecked Sendable {

    /// Analyse every n-th frame shown: the live pipeline also runs the detector on every 2nd frame.
    static let analysisStride = 2
    /// Phased · Auto crop geometry in Replay uses this source size (the live 48 MP camera), labelled.
    static let simulatedSourceMegapixels = 48.0

    /// Never started: the protocol needs a session; the preview in Replay is the video itself.
    let session = AVCaptureSession()
    let source: VideoReplaySource

    /// Light bookkeeping (run, counters, streams). Never blocked by the detector.
    private let analysisQueue = DispatchQueue(label: "gophoto.replay.state")
    /// The detector runs here, one frame at a time.
    private let workQueue = DispatchQueue(label: "gophoto.replay.detect")
    private let lock = NSLock()
    // Work-queue state.
    private var detector = PersonDetector()
    private var strict = false
    private var dims = false
    private var outline = false
    // State-queue state.
    private var busy = false
    private var run = 0
    private var stats = ReplayPipelineStats()
    private var latestFrame: ReplayFrame?

    private var personContinuation: AsyncStream<PersonDetection?>.Continuation?
    private var previewContinuation: AsyncStream<ReplayPreviewFrame>.Continuation?
    private var endContinuation: AsyncStream<ReplayEnd>.Continuation?
    private let ciContext = CIContext()
    /// Zoom / control intents from the guide (logged by the ViewModel; never applied).
    private(set) var zoomIntents = 0

    init(source: VideoReplaySource) {
        self.source = source
        super.init()
        source.onFrame = { [weak self] frame in self?.handle(frame) }
        source.onEnd = { [weak self] run, completed, why in
            self?.endContinuation?.yield(ReplayEnd(run: run, completed: completed, why: why))
        }
    }

    // MARK: Runs

    /// A new run from the start of the video: fresh detector (no tracker / lock / pose cadence
    /// carried over), counters cleared, paused.
    func restart(run newRun: Int) {
        analysisQueue.sync {
            run = newRun
            busy = false
            stats = ReplayPipelineStats()
            latestFrame = nil
        }
        workQueue.sync {
            detector = PersonDetector()
            detector.includeOutline = outline
            detector.strictLock = strict
            detector.wantsDimMask = dims
        }
        source.reset(run: newRun)
    }

    func play() { source.play() }
    func pause() { source.pause() }

    func currentStats() -> ReplayPipelineStats { analysisQueue.sync { stats } }

    /// The frame shown last (for "Save test frame").
    func lastFrame() -> ReplayFrame? { analysisQueue.sync { latestFrame } }

    func previewFrames() -> AsyncStream<ReplayPreviewFrame> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            analysisQueue.async { self.previewContinuation = continuation }
        }
    }

    func endEvents() -> AsyncStream<ReplayEnd> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            analysisQueue.async { self.endContinuation = continuation }
        }
    }

    // MARK: Frames (decode queue → analysis queue)

    private func handle(_ frame: ReplayFrame) {
        // Preview: every frame, scaled down (display only).
        let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let scale = min(1, 960 / max(image.extent.height, 1))
        let preview = ciContext.createCGImage(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
                                              from: image.extent.applying(CGAffineTransform(scaleX: scale, y: scale)))
        analysisQueue.async {
            guard frame.run == self.run else { return }
            self.stats.shown += 1
            self.latestFrame = frame
            if let preview {
                self.previewContinuation?.yield(ReplayPreviewFrame(image: preview, mediaTime: frame.mediaTime, run: frame.run))
            }
            guard frame.index % Self.analysisStride == 0 else { return }
            if self.busy { self.stats.droppedBusy += 1; return }
            self.busy = true
            // Bounded: one analysis at a time; frames arriving meanwhile are dropped (no backlog).
            self.workQueue.async { self.analyse(frame) }
        }
    }

    /// Work queue.
    private func analyse(_ frame: ReplayFrame) {
        let start = ProcessInfo.processInfo.systemUptime
        var detection = detector.detect(in: frame.pixelBuffer)
            // Nobody this frame: still a frame with a time, so the guide's clock moves on.
            ?? { var empty = PersonDetection(box: .zero); empty.subjectLocked = false; return empty }()
        let end = ProcessInfo.processInfo.systemUptime
        detection.mediaTime = frame.mediaTime
        detection.replayRun = frame.run
        detection.zoomFactor = 1            // no zoom is ever applied to a video
        detection.isZooming = false
        detection.verticalFOV = nil         // unknown for a video: missing, not guessed
        detection.photoMegapixels = nil
        let result = detection
        analysisQueue.async {
            self.busy = false
            guard frame.run == self.run else { return }      // a restart happened meanwhile: stale
            self.stats.analysed += 1
            self.stats.analysisSum += end - start
            let lag = end - frame.shownAt
            self.stats.lagSum += lag
            self.stats.lagMax = max(self.stats.lagMax, lag)
            self.personContinuation?.yield(result)
        }
    }

    // MARK: CameraServiceProtocol (action sink)

    func requestPermission() async -> CameraPermission { .granted }
    func configure() async throws {}
    func start() async {}
    func stop() async { source.pause() }

    func capturePhoto(onShutter: @escaping @Sendable () -> Void) async throws -> CapturedPhoto {
        throw ReplayError2.noCamera
    }

    func personDetections() -> AsyncStream<PersonDetection?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            analysisQueue.async { self.personContinuation = continuation }
            continuation.onTermination = { _ in self.analysisQueue.async { self.personContinuation = nil } }
        }
    }

    /// No scene model on video frames in this version: no signal.
    func environmentUpdates() -> AsyncStream<LiveEnvironmentSignal?> { AsyncStream { $0.finish() } }

    func zoomUpdates() -> AsyncStream<Double?> {
        AsyncStream { continuation in
            continuation.yield(1)
            continuation.finish()
        }
    }

    func setOutlineEnabled(_ enabled: Bool) {
        workQueue.async { self.outline = enabled; self.detector.includeOutline = enabled }
    }
    func setHighResolution(_ enabled: Bool) {}

    var currentZoom: Double? { 1 }
    /// Min = max = 1: automatic zoom has nothing to do, so no guide ever waits for a zoom.
    var minAvailableZoom: Double? { 1 }
    var maxAvailableZoom: Double? { 1 }

    func applyZoom(_ factor: Double) async -> Double {
        lock.withLock { zoomIntents += 1 }
        return 1                             // not applied (logged by the ViewModel)
    }

    func setDepthCapture(_ enabled: Bool) async -> Bool { false }

    func setStrictSubjectLock(_ enabled: Bool) {
        workQueue.async { self.strict = enabled; self.detector.strictLock = enabled }
    }
    func setSelectionDimming(_ enabled: Bool) {
        workQueue.async { self.dims = enabled; self.detector.wantsDimMask = enabled }
    }
    func lockSubject(to box: CGRect) {
        workQueue.async { self.detector.lock(to: box) }
    }

    var nativeZoomFactors: [Double] { [] }

    func setLiveDepth(_ enabled: Bool) async -> LiveDepthSupport {
        LiveDepthSupport(available: false, note: "This video has no depth data")
    }

    func depthUpdates() -> AsyncStream<LiveDepthFrame> { AsyncStream { $0.finish() } }
}

/// The video stopped: at its end, or interrupted (reader failure).
nonisolated struct ReplayEnd: Sendable {
    let run: Int
    let completed: Bool
    let why: String
}

/// A preview image of the video (display only).
nonisolated struct ReplayPreviewFrame: @unchecked Sendable {
    let image: CGImage
    let mediaTime: Double
    let run: Int
}
