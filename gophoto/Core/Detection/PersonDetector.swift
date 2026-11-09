//
//  PersonDetector.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 11/10/26.
//
//
//  PersonDetector.swift
//  gophoto
//
//  Core layer: the ONLY place that uses Apple's Vision framework.
//  Input: one camera frame. Output: where the person is.
//
import Vision
import CoreVideo
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Result for one camera frame: ONE person (the largest), never more.
nonisolated struct PersonDetection: @unchecked Sendable {
    /// Box around the person (normalized 0...1, origin TOP-LEFT). Used for alignment.
    let box: CGRect
    /// Face of that person (normalized, origin TOP-LEFT), when Vision found one inside the box.
    var face: CGRect? = nil
    /// Vertical field of view of the upright frame, degrees (set by `CameraService`).
    var verticalFOV: Double? = nil
    /// Largest photo the camera can take, megapixels (set by `CameraService`).
    var photoMegapixels: Double? = nil
    /// White ring around the body on a transparent background, covering the whole frame.
    /// Only made when `PersonDetector.includeOutline` is on (guide mode "A · Old look").
    var outline: CGImage? = nil
    /// Sitting / standing read from this frame's body pose. Nil when the pose was not run this
    /// frame (it runs every `PersonDetector.poseInterval` frames) or the legs are not visible.
    var posture: BodyPosture? = nil
    /// Reliable body joints inside the frame, from this frame's pose (nil when the pose was not
    /// run this frame). The guide checks where the frame cuts the body with them (version 17):
    /// real joints, so it does not assume body proportions.
    var visibleJoints: Set<BodyJoint>? = nil
    /// Zoom factor of this frame, and whether a zoom ramp was running (set by `CameraService`).
    /// Boxes from different zooms must not be mixed, and a moving zoom is not judged.
    var zoomFactor: Double? = nil
    var isZooming = false

    // Phased guide (strict lock, `PersonDetector.strictLock`). Other guides leave these defaults.
    /// Every person box this frame (normalized, origin top-left).
    var candidates: [CGRect] = []
    /// `box` is the locked subject. False (strict lock only): nobody is locked; `box` is empty and
    /// only `candidates` count.
    var subjectLocked = true
    /// Reliable joints of the subject's pose (normalized, origin top-left), when the pose ran.
    var landmarks: [BodyLandmark]? = nil
    /// The subject's instance mask: bounding box (hair and clothes included) and the frame edges
    /// it touches, when the mask ran this frame.
    var extent: CGRect? = nil
    var extentEdges: FrameEdges = []
    /// Selection UI: semi-transparent black where no person is, clear on people (frame size).
    var dimMask: CGImage? = nil

    // Video replay (appMode 2 testing): the frame's media time and the run it belongs to.
    var mediaTime: TimeInterval? = nil
    var replayRun: Int? = nil
}

nonisolated final class PersonDetector {

    // Where the person is (for alignment)
    private let boxRequest: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false
        return request
    }()

    // The person's face (eye line and head size for the camera-height and distance guide)
    private let faceRequest = VNDetectFaceRectanglesRequest()

    // The person's skeleton, only to tell sitting from standing (shot size options). Posture
    // changes slowly, so it runs every few detections to keep the camera smooth.
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    static let poseInterval = 3
    private var detectionCount = 0

    /// Draw the body outline too (costly: person segmentation every frame). Old-look mode only.
    var includeOutline = false

    // The person's shape (for the old-look outline)
    private let maskRequest: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private let ciContext = CIContext()

    // Outline look, as a fraction of the mask's width
    private let gapRatio: CGFloat = 0.025   // space between body and line
    private let lineRatio: CGFloat = 0.012  // line thickness

    // Subject lock: once a person is chosen, follow THAT person (box overlap) instead of
    // re-picking the largest every frame, so the guide never jumps to someone else.
    private var lockedBox: CGRect?
    private var missedFrames = 0
    /// Detection frames the locked person may be missing before another person can be chosen.
    private let maxMissedFrames = 15
    private let minOverlap: CGFloat = 0.15

    // Tracker: follows the locked person between detections. Vision's person detector misses
    // frames (turned away, arms up, partly hidden); the tracker keeps the box so the guide does
    // not reset. Seeded from the detector, re-seeded when the two disagree.
    private let sequenceHandler = VNSequenceRequestHandler()
    private var trackRequest: VNTrackObjectRequest?
    /// Frames in a row that only the tracker found the person; the detector must confirm in time.
    private var trackedOnlyFrames = 0
    private let maxTrackedOnlyFrames = 60
    private let minTrackConfidence: Float = 0.3
    /// Below this overlap between tracker and detector, the tracker is re-seeded.
    private let reseedOverlap: CGFloat = 0.6

    /// Phased guide: never choose a person on its own (no "largest person" pick, no fallback):
    /// only `lock(to:)` chooses, and a person lost for good is released, not replaced.
    var strictLock = false {
        didSet { if strictLock != oldValue { resetSubjectLock() } }
    }
    /// Phased guide: build `dimMask` (while the photographer chooses a person).
    var wantsDimMask = false

    // Each person's own mask (Phased): coverage incl. clothes, and the dimming for the selection.
    private let instanceRequest = VNGeneratePersonInstanceMaskRequest()

    /// Phased guide: follow the person in `box` (top-left origin) from now on.
    func lock(to box: CGRect) {
        lockedBox = box
        missedFrames = 0
        trackedOnlyFrames = 0
        seedTracker(box)
    }

    /// Forget the locked person (the next detection picks the largest again).
    func resetSubjectLock() {
        lockedBox = nil
        missedFrames = 0
        trackRequest = nil
        trackedOnlyFrames = 0
    }

    /// Starts tracking `box` (top-left origin) from this frame on.
    private func seedTracker(_ box: CGRect) {
        let visionBox = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        let request = VNTrackObjectRequest(detectedObjectObservation: VNDetectedObjectObservation(boundingBox: visionBox))
        request.trackingLevel = .fast          // .accurate made the whole camera sluggish
        trackRequest = request
    }

    /// The tracked person's box in this frame (top-left origin), or nil when the tracker lost it.
    private func track(_ pixelBuffer: CVPixelBuffer) -> CGRect? {
        guard let request = trackRequest else { return nil }
        do {
            try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
        } catch {
            trackRequest = nil
            return nil
        }
        guard let observation = request.results?.first as? VNDetectedObjectObservation,
              observation.confidence >= minTrackConfidence else {
            trackRequest = nil
            return nil
        }
        request.inputObservation = observation        // continue from here next frame
        let b = observation.boundingBox
        return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
    }

    /// Runs the requests on one upright frame. nil = nobody found (or the locked person is
    /// briefly hidden). Only one person is used; anyone else in the frame is ignored.
    func detect(in pixelBuffer: CVPixelBuffer) -> PersonDetection? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        detectionCount += 1
        let readsPose = detectionCount.isMultiple(of: Self.poseInterval)
        var requests: [VNRequest] = [boxRequest, faceRequest]
        if includeOutline { requests.append(maskRequest) }
        if readsPose { requests.append(poseRequest) }
        let readsInstances = strictLock && (readsPose || (wantsDimMask && detectionCount.isMultiple(of: 2)))
        if readsInstances { requests.append(instanceRequest) }
        do {
            try handler.perform(requests)
        } catch {
            return nil
        }

        // Vision's origin is BOTTOM-left; SwiftUI's is TOP-left → flip Y
        let boxes = (boxRequest.results ?? []).map { r -> CGRect in
            let b = r.boundingBox
            return CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
        }

        // Where the tracker thinks the locked person is now (runs every frame to stay warm).
        let tracked = lockedBox != nil ? track(pixelBuffer) : nil
        func match(_ candidate: CGRect) -> CGFloat {
            max(lockedBox.map { Self.overlap(candidate, $0) } ?? 0, tracked.map { Self.overlap(candidate, $0) } ?? 0)
        }

        let box: CGRect
        if lockedBox != nil,
           let best = boxes.max(by: { match($0) < match($1) }), match(best) >= minOverlap {
            box = best                                   // same person as before
            trackedOnlyFrames = 0
            if tracked.map({ Self.overlap($0, best) < reseedOverlap }) ?? true { seedTracker(best) }
        } else if let tracked, trackedOnlyFrames < maxTrackedOnlyFrames {
            box = tracked                                // detector missed: the tracker still has them
            trackedOnlyFrames += 1
        } else if lockedBox != nil, missedFrames < maxMissedFrames {
            missedFrames += 1                            // locked person hidden for a moment: wait
            return strictLock ? candidatesOnly(boxes, readsInstances: readsInstances) : nil
        } else if strictLock {
            // Strict: nobody locked, or the locked person is gone. Never pick someone else here.
            if lockedBox != nil { resetSubjectLock() }
            return boxes.isEmpty && !wantsDimMask ? nil : candidatesOnly(boxes, readsInstances: readsInstances)
        } else if let largest = boxes.max(by: { $0.width * $0.height < $1.width * $1.height }) {
            box = largest                                // first person, or the old one is gone
            trackedOnlyFrames = 0
            seedTracker(largest)
        } else {
            resetSubjectLock()
            return nil
        }
        lockedBox = box
        missedFrames = 0

        // Largest face whose centre lies inside that person's box
        let face = faceRequest.results?
            .map { f -> CGRect in
                let r = f.boundingBox
                return CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
            }
            .filter { box.contains(CGPoint(x: $0.midX, y: $0.midY)) }
            .max { $0.height < $1.height }

        let outline = includeOutline ? maskRequest.results?.first.flatMap { makeOutline(from: $0.pixelBuffer) } : nil
        let pose = readsPose ? pose(of: poseRequest.results ?? [], in: box) : nil
        let posture = pose.flatMap { PostureClassifier.posture(of: $0) }
        let visible: Set<BodyJoint>? = readsPose ? Set((pose?.reliableLandmarks() ?? []).filter {
            $0.point.y >= Self.frameEdge && $0.point.y <= 1 - Self.frameEdge
                && $0.point.x >= Self.frameEdge && $0.point.x <= 1 - Self.frameEdge
        }.map(\.joint)) : nil
        var detection = PersonDetection(box: box, face: face, outline: outline, posture: posture, visibleJoints: visible)
        if strictLock {
            detection.candidates = boxes
            if readsPose { detection.landmarks = pose?.reliableLandmarks() ?? [] }
            if readsInstances, let labels = instanceLabels() {
                if let mine = labels.instances.max(by: { Self.overlap($0.box, box) < Self.overlap($1.box, box) }),
                   Self.overlap(mine.box, box) > 0.2 {
                    detection.extent = mine.box
                    detection.extentEdges = mine.edges
                }
                if wantsDimMask { detection.dimMask = labels.dim }
            }
        }
        return detection
    }

    /// Strict lock without a locked subject: the people this frame (and the dimming), nothing else.
    private func candidatesOnly(_ boxes: [CGRect], readsInstances: Bool) -> PersonDetection {
        var detection = PersonDetection(box: .zero)
        detection.subjectLocked = false
        detection.candidates = boxes
        if readsInstances, wantsDimMask { detection.dimMask = instanceLabels()?.dim }
        return detection
    }

    // MARK: - Person instances (Phased)

    private struct Instance { var box: CGRect; var edges: FrameEdges }

    /// Each person's mask box and touched edges from the last instance-mask request, and the
    /// dimming image (when `wantsDimMask`).
    private func instanceLabels() -> (instances: [Instance], dim: CGImage?)? {
        // Each person's own mask via `generateMask(forInstances:)` (documented path; the first version
        // read the label image directly and every person came out as the whole frame).
        guard let observation = instanceRequest.results?.first else { return nil }
        var instances: [Instance] = []
        for index in observation.allInstances {
            guard let mask = try? observation.generateMask(forInstances: IndexSet(integer: index)),
                  let cover = Self.coverage(of: mask, dim: false), cover.box.width > 0 else { continue }
            // A "person" filling the whole frame is not a usable reading.
            if cover.box.width > 0.98, cover.box.height > 0.98 { continue }
            instances.append(Instance(box: cover.box, edges: cover.edges))
        }
        var image: CGImage?
        if wantsDimMask, let all = try? observation.generateMask(forInstances: observation.allInstances) {
            image = Self.coverage(of: all, dim: true)?.dim
        }
        return (instances, image)
    }

    /// Normalized box of the mask's person pixels (> 0.5), the frame edges they touch, and (optionally)
    /// the dimming image (black 55% where no person is). Reads 8-bit, 16-bit half and 32-bit float masks.
    nonisolated static func coverage(of buffer: CVPixelBuffer, dim: Bool)
        -> (box: CGRect, edges: FrameEdges, dim: CGImage?)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        func value(_ row: UnsafeRawPointer, _ x: Int) -> Float {
            switch format {
            case kCVPixelFormatType_OneComponent32Float:
                return row.load(fromByteOffset: x * 4, as: Float32.self)
            case kCVPixelFormatType_OneComponent16Half:
                return Float(Float16(bitPattern: row.load(fromByteOffset: x * 2, as: UInt16.self)))
            default:
                return Float(row.load(fromByteOffset: x, as: UInt8.self)) / 255
            }
        }
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        var pixels: [UInt8] = dim ? [UInt8](repeating: 0, count: w * h * 4) : []
        for y in 0..<h {
            let row = UnsafeRawPointer(base.advanced(by: y * rowBytes))
            for x in 0..<w {
                if value(row, x) > 0.5 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                } else if dim {
                    pixels[(y * w + x) * 4 + 3] = 140          // black, premultiplied
                }
            }
        }
        var image: CGImage?
        if dim {
            let space = CGColorSpaceCreateDeviceRGB()
            image = pixels.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
            }
        }
        guard maxX >= 0 else { return (CGRect.zero, [], image) }
        let edgeX = max(1, w / 100), edgeY = max(1, h / 100)
        var edges: FrameEdges = []
        if minY < edgeY { edges.insert(.top) }
        if maxY >= h - edgeY { edges.insert(.bottom) }
        if minX < edgeX { edges.insert(.left) }
        if maxX >= w - edgeX { edges.insert(.right) }
        let box = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                         width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
        return (box, edges, image)
    }

    // MARK: - Posture (sitting / standing)

    /// A joint closer than this to the frame edge counts as cut off.
    static let frameEdge: CGFloat = 0.01

    /// The skeleton that belongs to the locked person's box (same rule as the photo analysis).
    private func pose(of observations: [VNHumanBodyPoseObservation], in box: CGRect) -> PoseCandidate? {
        let poses = observations.compactMap { observation -> PoseCandidate? in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let landmarks = points.compactMap { name, point -> BodyLandmark? in
                guard let joint = Self.joint(name, extended: strictLock) else { return nil }
                // Vision's origin is BOTTOM-left → flip Y
                return BodyLandmark(joint: joint, point: CGPoint(x: point.location.x, y: 1 - point.location.y),
                                    confidence: Double(point.confidence))
            }
            return PoseCandidate(landmarks: landmarks, observationConfidence: Double(observation.confidence))
        }
        return SubjectAssociation.pose(for: box, among: poses)
    }

    /// The joints the posture rule reads (others are skipped). Phased (`extended`) also reads the
    /// eyes, ears, elbows and wrists: the head-from-pose vantage fallback needs them.
    private static func joint(_ name: VNHumanBodyPoseObservation.JointName, extended: Bool = false) -> BodyJoint? {
        if extended {
            switch name {
            case .leftEye: return .leftEye
            case .rightEye: return .rightEye
            case .leftEar: return .leftEar
            case .rightEar: return .rightEar
            case .leftElbow: return .leftElbow
            case .rightElbow: return .rightElbow
            case .leftWrist: return .leftWrist
            case .rightWrist: return .rightWrist
            default: break
            }
        }
        return switch name {
        case .neck: .neck
        case .leftShoulder: .leftShoulder
        case .rightShoulder: .rightShoulder
        case .root: .root
        case .leftHip: .leftHip
        case .rightHip: .rightHip
        case .leftKnee: .leftKnee
        case .rightKnee: .rightKnee
        case .leftAnkle: .leftAnkle
        case .rightAnkle: .rightAnkle
        case .nose: .nose
        default: nil
        }
    }

    /// Intersection over union of two boxes (0 = apart, 1 = identical).
    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    // MARK: - Mask → ring with a gap (old look)

    private func makeOutline(from mask: CVPixelBuffer) -> CGImage? {
        let maskImage = CIImage(cvPixelBuffer: mask)
        let extent = maskImage.extent
        let gap = extent.width * gapRatio
        let line = extent.width * lineRatio

        // 1. Soften jagged edges
        let smooth = maskImage.clampedToExtent().applyingGaussianBlur(sigma: 2)

        // 2. Grow the body shape: once by the gap, once by gap + line
        let inner = grow(smooth, by: gap)
        let outer = grow(smooth, by: gap + line)

        // 3. Outer minus inner = a ring floating around the body
        let subtract = CIFilter.subtractBlendMode()
        subtract.inputImage = inner
        subtract.backgroundImage = outer
        guard let ring = subtract.outputImage?.cropped(to: extent) else { return nil }

        // 4. White → visible, black → transparent
        let toAlpha = CIFilter.maskToAlpha()
        toAlpha.inputImage = ring
        guard let output = toAlpha.outputImage else { return nil }

        return ciContext.createCGImage(output, from: extent)
    }

    /// "Grows" white areas outward by `radius` pixels (called dilation).
    private func grow(_ image: CIImage, by radius: CGFloat) -> CIImage {
        let filter = CIFilter.morphologyMaximum()
        filter.inputImage = image
        filter.radius = Float(radius)
        return filter.outputImage ?? image
    }
}
