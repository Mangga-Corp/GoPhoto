//
//  VideoReplaySource.swift
//  gophoto
//
//  appMode 2 testing: plays a local video at 1× by its presentation timestamps, frame by frame,
//  upright (the track's preferred transform is applied by the video composition, so a vertical
//  phone video comes out vertical). No seeking: "restart" opens a new reader from the start.
//  Spec: Docs/Experiments/Replay/Spec.md §3, §7.
//
import AVFoundation
import CoreImage
import CryptoKit
import Foundation

/// What the replay knows about a video (audited, not guessed).
nonisolated struct ReplayVideoInfo: Sendable, Equatable {
    var name: String
    var url: URL
    var duration: Double
    /// Upright display size (after the preferred transform), pixels.
    var uprightSize: CGSize
    /// Pixel size stored in the track before the transform.
    var trackSize: CGSize
    var nominalFrameRate: Double
    /// Rotation of the preferred transform, degrees, and whether it mirrors.
    var rotation: Double
    var mirrored: Bool
    var sha256: String
    /// Tracks other than video / audio found in the file (e.g. depth, metadata). Not used as sensors:
    /// there is no synchronized recorder format in this app yet.
    var extraTracks: [String]
    var hasDepthTrack: Bool

    var aspect: Double { uprightSize.height > 0 ? Double(uprightSize.width / uprightSize.height) : 0.75 }
    var label: String { String(format: "%@ · %.1f s · %.0f×%.0f · %.0f fps", name, duration, uprightSize.width, uprightSize.height, nominalFrameRate) }
}

nonisolated enum ReplayError: LocalizedError {
    case noVideoTrack, cannotRead(String)
    var errorDescription: String? {
        switch self {
        case .noVideoTrack: "This file has no video track."
        case .cannotRead(let why): "Couldn't read the video: \(why)"
        }
    }
}

/// One decoded frame, upright.
nonisolated struct ReplayFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    /// Presentation time, seconds from the start of the video.
    let mediaTime: Double
    let index: Int
    let run: Int
    /// Wall clock (system uptime) when the frame was shown.
    let shownAt: TimeInterval
}

nonisolated final class VideoReplaySource: @unchecked Sendable {
    enum State: String, Sendable { case idle, playing, paused, ended }

    let info: ReplayVideoInfo
    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let composition: AVVideoComposition
    private let queue = DispatchQueue(label: "gophoto.replay.decode")

    // Decode-queue state.
    private var reader: AVAssetReader?
    private var output: AVAssetReaderVideoCompositionOutput?
    private var state: State = .idle
    private var run = 0
    private var index = 0
    /// 1× pacing: media time `anchorMedia` is shown at wall time `anchorWall`.
    private var anchorWall: TimeInterval = 0
    private var anchorMedia: Double = 0
    private var mediaTime: Double = 0
    /// The next frame, read but not shown yet (kept across a pause).
    private var pending: (buffer: CVPixelBuffer, time: Double)?
    private var lateFrames = 0

    /// Called on the decode queue for every frame shown (1× media time).
    var onFrame: (@Sendable (ReplayFrame) -> Void)?
    /// Called on the decode queue when the video stops: run id, and whether it really reached the
    /// end (false = the reader failed, e.g. the app went to the background; the run is not complete).
    var onEnd: (@Sendable (_ run: Int, _ completed: Bool, _ why: String) -> Void)?

    private init(info: ReplayVideoInfo, asset: AVURLAsset, track: AVAssetTrack, composition: AVVideoComposition) {
        self.info = info
        self.asset = asset
        self.track = track
        self.composition = composition
    }

    /// Opens and audits a local video.
    static func open(_ url: URL) async throws -> VideoReplaySource {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ReplayError.noVideoTrack }
        let (natural, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let duration = try await asset.load(.duration).seconds
        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        let upright = CGRect(origin: .zero, size: natural).applying(transform).standardized.size
        let rotation = atan2(Double(transform.b), Double(transform.a)) * 180 / .pi
        let mirrored = transform.a * transform.d - transform.b * transform.c < 0
        var extra: [String] = []
        var depth = false
        for t in try await asset.load(.tracks) where t.mediaType != .video && t.mediaType != .audio {
            extra.append(t.mediaType.rawValue)
            if t.mediaType == .depthData { depth = true }
        }
        let info = ReplayVideoInfo(name: url.lastPathComponent, url: url, duration: duration,
                                   uprightSize: upright, trackSize: natural, nominalFrameRate: Double(rate),
                                   rotation: rotation, mirrored: mirrored, sha256: Self.sha256(of: url),
                                   extraTracks: extra, hasDepthTrack: depth)
        return VideoReplaySource(info: info, asset: asset, track: track, composition: composition)
    }

    private static func sha256(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "—" }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Control (any thread)

    /// Starts a new run from the beginning (paused). Frames of older runs are never delivered.
    func reset(run newRun: Int) {
        queue.async {
            self.reader?.cancelReading()
            self.run = newRun
            self.index = 0
            self.mediaTime = 0
            self.pending = nil
            self.lateFrames = 0
            self.state = .paused
            do {
                let reader = try AVAssetReader(asset: self.asset)
                let output = AVAssetReaderVideoCompositionOutput(
                    videoTracks: [self.track],
                    videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
                output.videoComposition = self.composition
                guard reader.canAdd(output) else { throw ReplayError.cannotRead("output not supported") }
                reader.add(output)
                guard reader.startReading() else { throw ReplayError.cannotRead(reader.error?.localizedDescription ?? "?") }
                self.reader = reader
                self.output = output
            } catch {
                NSLog("GoPhoto replay reader: %@", error.localizedDescription)
                self.state = .ended
                self.reader = nil
                self.output = nil
            }
        }
    }

    func play() {
        queue.async {
            guard self.state == .paused || self.state == .idle else { return }
            self.state = .playing
            self.anchorWall = ProcessInfo.processInfo.systemUptime
            self.anchorMedia = self.pending?.time ?? self.mediaTime
            self.pump(run: self.run)
        }
    }

    func pause() {
        queue.async { if self.state == .playing { self.state = .paused } }
    }

    func stop() {
        queue.async {
            self.state = .idle
            self.reader?.cancelReading()
            self.reader = nil
            self.output = nil
            self.pending = nil
        }
    }

    /// Late frames (shown after their time by more than a frame), for the run summary.
    func stats(_ done: @escaping @Sendable (_ state: State, _ mediaTime: Double, _ late: Int) -> Void) {
        queue.async { done(self.state, self.mediaTime, self.lateFrames) }
    }

    // MARK: Decode queue

    /// Reads the next frame and shows it at its media time; then the next one.
    private func pump(run current: Int) {
        guard state == .playing, current == run else { return }
        if pending == nil {
            guard let output, let sample = output.copyNextSampleBuffer(),
                  let buffer = CMSampleBufferGetImageBuffer(sample) else {
                state = .ended
                let status = reader?.status
                let completed = status == .completed
                let why = completed ? "video ended"
                    : "reader stopped (\(reader?.error?.localizedDescription ?? "status \(status?.rawValue ?? -1)"))"
                onEnd?(run, completed, why)
                return
            }
            pending = (buffer, CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        }
        guard let next = pending else { return }
        let due = anchorWall + (next.time - anchorMedia)
        let wait = due - ProcessInfo.processInfo.systemUptime
        if wait > 0.002 {
            queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.pump(run: current) }
            return
        }
        if wait < -1.0 / max(info.nominalFrameRate, 1) { lateFrames += 1 }
        pending = nil
        mediaTime = next.time
        index += 1
        onFrame?(ReplayFrame(pixelBuffer: next.buffer, mediaTime: next.time, index: index, run: run,
                             shownAt: ProcessInfo.processInfo.systemUptime))
        queue.async { [weak self] in self?.pump(run: current) }
    }
}
