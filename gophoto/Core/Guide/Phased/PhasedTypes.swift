//
//  PhasedTypes.swift
//  gophoto
//
//  Phased guide (appMode 2 experiment): types shared by the four Phased variants.
//  Pure values: no sensors, no UI. Spec: Docs/Experiments/PhaseGuide/Spec-v3.md §3–9.
//
import CoreGraphics
import Foundation

/// Where the photographer is in the guide. One phase is finished before the next starts.
nonisolated enum PhasedPhase: String, Sendable, Codable, CaseIterable {
    /// 0 — a subject is locked and readable; the zoom for the rest of the guide is chosen.
    case acquire
    /// 1 — a distance that leaves room for the final framing and for the next phases.
    case distance
    /// 2 — phone height (vantage) against the reference.
    case vantage
    /// 3 — tilt: the final framing must be reachable, then the reference pitch.
    case tilt
    /// 4 — final framing (crop or no crop); "Take the photo now" when everything is valid.
    case framing

    var number: Int {
        switch self {
        case .acquire: 0
        case .distance: 1
        case .vantage: 2
        case .tilt: 3
        case .framing: 4
        }
    }
}

/// One instruction at a time. No steps, no centimetres, no per-phase "OK".
nonisolated enum PhasedInstruction: String, Sendable, Equatable, CaseIterable, Codable {
    case tapPerson, moveCloser, moveBack, raisePhone, lowerPhone, tiltUp, tiltDown, pointBack, holdIt, takePhoto
    /// Auto crop (11 Nov): the crop cannot put the person where the reference has them → turn the phone.
    /// Directions are for the photographer: moving the phone left slides the person RIGHT in the picture.
    case moveLeft, moveRight
    /// 12 Nov: horizon 2–5° off → straighten the phone (beyond that it is left as a Dutch angle).
    case levelPhone

    var text: String {
        switch self {
        case .tapPerson:  "Tap the person to photograph"
        case .moveCloser: "Move closer"
        case .moveBack:   "Move back"
        case .raisePhone: "Raise the phone"
        case .lowerPhone: "Lower the phone"
        case .tiltUp:     "Tilt up"
        case .tiltDown:   "Tilt down"
        case .pointBack:  "Point back at the person"
        case .holdIt:     "Hold it there"
        case .takePhoto:  "Take the photo now"
        case .moveLeft:   "Move the phone left"
        case .moveRight:  "Move the phone right"
        case .levelPhone: "Straighten the phone"
        }
    }

    var symbol: String {
        switch self {
        case .tapPerson:  "hand.tap"
        case .moveCloser: "figure.walk"
        case .moveBack:   "arrow.uturn.backward"
        case .raisePhone: "arrow.up.to.line"
        case .lowerPhone: "arrow.down.to.line"
        case .tiltUp:     "arrow.up.circle"
        case .tiltDown:   "arrow.down.circle"
        case .pointBack:  "viewfinder"
        case .holdIt:     "hand.raised"
        case .takePhoto:  "camera"
        case .moveLeft:   "arrow.left"
        case .moveRight:  "arrow.right"
        case .levelPhone: "level"
        }
    }

    /// The existing motion overlay's animation (rotation for tilt, translation for height).
    var motion: GuideInstruction? {
        switch self {
        case .raisePhone: .raisePhone
        case .lowerPhone: .lowerPhone
        case .tiltUp:     .tiltUp
        case .tiltDown:   .tiltDown
        default:          nil
        }
    }
}

/// Shot sizes the Phased guide supports. One-quarter is not supported yet; sitting uses full.
nonisolated enum PhasedShot: String, Sendable, Codable {
    case full, threeQuarter, half

    init?(_ shot: PresetAnalysis.ShotSize) {
        switch shot {
        case .full: self = .full
        case .threeQuarter: self = .threeQuarter
        case .half: self = .half
        case .quarter: return nil
        }
    }
}

/// Frame edges (an instance mask touching them = possible clipping).
nonisolated struct FrameEdges: OptionSet, Sendable, Equatable, Hashable {
    let rawValue: Int
    static let top = FrameEdges(rawValue: 1)
    static let bottom = FrameEdges(rawValue: 2)
    static let left = FrameEdges(rawValue: 4)
    static let right = FrameEdges(rawValue: 8)

    var label: String {
        var parts: [String] = []
        if contains(.top) { parts.append("top") }
        if contains(.bottom) { parts.append("bottom") }
        if contains(.left) { parts.append("left") }
        if contains(.right) { parts.append("right") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}

/// What the reference photos ask for, for one shot size (from the preset analysis, v18).
nonisolated struct PhasedTarget: Sendable, Equatable {
    var shot: PhasedShot
    /// Reference span in frame-height units: full = person box height; 3/4 and half = head top to
    /// the frame bottom (their references are cut there). Nil = no reference size.
    var span: Double?
    /// Reference top of the person and horizontal centre (frame units, origin top-left).
    var top: Double?
    var midX: Double?
    /// Camera height vs the eyes in face heights (v17, + = camera above the eyes).
    var vantageFaces: Double?
    /// Fallback: camera height vs the eyes as an angle (degrees), when face units are missing.
    var vantageDegrees: Double?
    /// Reference phone pitch (`DeviceTilt`, + = down) when the references agree on an angle.
    var pitch: Double?
    var sitting: Bool

    /// The target for `shot`, or a reason why the Phased guide cannot guide it.
    static func make(analysis: PresetAnalysis?, shot: PresetAnalysis.ShotSize?,
                     posture: BodyPosture?) -> (target: PhasedTarget?, reason: String?) {
        guard let analysis else { return (nil, "no preset analysis") }
        let sitting = posture == .sitting
        let wanted: PresetAnalysis.ShotSize? = sitting ? PresetAnalysis.ShotSize.full : shot
        guard let picked = wanted else { return (nil, "no shot size") }
        guard let phased = PhasedShot(picked) else { return (nil, "1/4 is not supported by Phased yet") }
        let box = analysis.subjectBox
        var pitch: Double?
        if case .match(_, let down) = analysis.angle { pitch = down }
        let target = PhasedTarget(shot: phased,
                                  span: box.map { Double($0.height) },
                                  top: box.map { Double($0.minY) },
                                  midX: box.map { Double($0.midX) },
                                  vantageFaces: analysis.eyeOffsetFaces,
                                  vantageDegrees: analysis.eyeElevation,
                                  pitch: pitch,
                                  sitting: sitting)
        return (target, nil)
    }
}

/// The locked subject as measured in one detection (frame units, origin top-left).
nonisolated struct SubjectObservation: Sendable, Equatable {
    var box: CGRect
    var face: CGRect?
    /// Reliable joints of this person's pose (nil when the pose did not run recently).
    var landmarks: [BodyLandmark]?
    /// This person's instance mask bounding box (hair, clothes included) and the edges it touches.
    var extent: CGRect?
    var touches: FrameEdges = []
}

/// Native depth on the subject (Phased + Depth).
nonisolated struct DepthSample: Sendable, Equatable {
    /// Median over valid samples on the body surface: metres when `absolute`, else relative units.
    var value: Double
    /// Share of the body samples that were valid (0...1).
    var validFraction: Double
    var absolute: Bool
    var sampleCount: Int
    var time: TimeInterval
}

/// Everything the engine reads in one update.
nonisolated struct PhasedFrame: Sendable {
    var time: TimeInterval
    /// The locked subject's latest measurement, and when it was taken; nil = no locked subject.
    var subject: SubjectObservation?
    var detectionTime: TimeInterval?
    /// + = phone tilted down (`DeviceTilt`). Nil = no motion sensor for this frame (video replay):
    /// missing stays missing, never 0.
    var pitch: Double?
    var roll: Double?
    var phoneStill: Bool
    /// Vertical field of view of the frame the subject comes from (zoom included), degrees.
    var verticalFOV: Double?
    var zoom: Double?
    /// Zoom not moving and settled: measurements are comparable.
    var zoomStable: Bool
    /// 2× is a lens / sensor-crop zoom on this camera (else it would be digital).
    var nativeTwoX: Bool
    var depth: DepthSample?
    /// Width / height of the frame (3:4 live; the video's own aspect in Replay).
    var frameAspect: Double = 3.0 / 4.0
}

/// What the engine decided this update.
nonisolated struct PhasedOutput: Equatable, Sendable {
    var horizontalError: Double?
    var phase: PhasedPhase = .acquire
    var instruction: PhasedInstruction?
    /// Every phase is valid: "Take the photo now" (never blocks the shutter).
    var ready = false
    /// Auto crop: the crop valid now (frame units, origin top-left) and the roll to straighten, degrees.
    var cropWindow: CGRect?
    var cropRoll: Double = 0
    /// Auto crop: the crop the shutter uses right now (also before "ready"), and its roll.
    var captureCrop: CGRect?
    var captureRoll: Double = 0
    /// Bars: the size band's enter limits, and the tilt need (+ = tilt up, 1 = tolerance edge).
    var sizeEnterLow: Double?
    var sizeEnterHigh: Double?
    var tiltNeed: Double?
    /// Zoom the engine wants (1× / 2×); the ViewModel applies it once.
    var zoomRequest: Double?
    // Diagnostics (debug panel + log).
    var sizeRatio: Double?
    var sizeSource: String = "—"
    var vantageError: Double?
    var vantageUnit = "faces"
    /// "face" or "head + shoulders" (eyes not read).
    var vantageSource = "—"
    var tiltError: Double?
    var tiltSource: String = "—"
    var limitation: String?
    var reason: String = ""
    /// Inputs this update did not have (e.g. no motion sensor in a video): what could not be evaluated.
    var notEvaluated: [String] = []
}

/// A transition worth logging.
nonisolated struct PhasedEvent: Sendable, Equatable {
    var kind: String
    var detail: String
    var values: [String: Double] = [:]
}
