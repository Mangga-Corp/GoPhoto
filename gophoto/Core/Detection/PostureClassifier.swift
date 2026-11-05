//
//  PostureClassifier.swift
//  gophoto
//
//  Sitting or standing, from one 2D body pose. Used by the live camera (`PersonDetector`) and by
//  the preference analysis (`PreferenceAnalyzer`), so both read posture the same way.
//
//  Rule (vertical distances only, so the image's aspect ratio does not matter): with the torso
//  upright, a standing thigh hangs down about as long as the torso (neck joint → hip joint ≈
//  0.29 body heights, hip → knee ≈ 0.25, ratio ≈ 0.85). A seated thigh points forward or toward
//  the camera, so it barely drops (ratio near 0) while the shin still hangs down.
//
//  Limitation: the hips and knees must be visible. A seated person cut above the knees (3/4,
//  half body, 1/4) can't be told apart from a standing one, so sitting is only read in shots
//  that show the legs — in practice full body.
//

import CoreGraphics

nonisolated enum BodyPosture: String, Sendable, Codable, Hashable {
    case standing, sitting

    var title: String {
        switch self {
        case .standing: "Standing"
        case .sitting: "Sitting"
        }
    }
}

nonisolated enum PostureClassifier {
    /// Thigh drop (hip → knee, vertical) in torso lengths below which the person sits.
    static let sittingThighRatio = 0.45
    /// At or above this the person stands. In between: ambiguous (no reading).
    static let standingThighRatio = 0.65
    /// With the ankles visible: thigh drop / shin drop below this also means sitting
    /// (standing ≈ 1, seated with feet on the floor ≈ 0–0.4).
    static let sittingThighToShin = 0.5
    /// Torso shorter than this (frame heights) is too small or not upright to read.
    static let minTorso = 0.03

    /// Sitting / standing, or nil when the joints needed are not visible or the reading is ambiguous.
    /// Points are normalised with a TOP-LEFT origin (y grows downward).
    static func posture(of pose: PoseCandidate) -> BodyPosture? {
        func meanY(_ joints: [BodyJoint]) -> Double? {
            let ys = joints.compactMap { pose.reliable($0).map { Double($0.point.y) } }
            return ys.isEmpty ? nil : ys.reduce(0, +) / Double(ys.count)
        }
        guard let neck = meanY([.neck]) ?? meanY([.leftShoulder, .rightShoulder]),
              let hip = meanY([.leftHip, .rightHip]) ?? meanY([.root]),
              let knee = meanY([.leftKnee, .rightKnee]) else { return nil }
        let torso = hip - neck
        guard torso >= minTorso else { return nil }

        let thigh = (knee - hip) / torso
        if thigh < sittingThighRatio { return .sitting }
        if let ankle = meanY([.leftAnkle, .rightAnkle]) {
            let shin = (ankle - knee) / torso
            if shin > 0.4, thigh / shin < sittingThighToShin { return .sitting }
        }
        return thigh >= standingThighRatio ? .standing : nil
    }
}
