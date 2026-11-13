//
//  GroundTruth.swift
//  gophoto
//
//  appMode 2 "GT" recording (12 Nov): while on, the guide's live analysis is logged twice a second
//  ("track" lines) and every shutter keeps the original photo plus what the photographer measured
//  (ground truth). Later the main analysis (PreferenceAnalyzer / GeoCalib) runs on the same photos,
//  so live guide vs offline analysis vs measured truth can be compared photo by photo.
//  Files: Documents/GuideLogs/<session>/gt-<time>.<jpg|heic> and gt-<time>.json.
//
import Foundation

nonisolated struct GroundTruthEntry: Codable, Sendable, Identifiable, Equatable {
    /// Same id as the photo file and the capture note (`gtID`).
    var id: String
    /// Measured with a tape: lens height and the subject's eye height above the floor, cm.
    var cameraHeightCm: Double? = nil
    var eyeHeightCm: Double? = nil
    /// When not measured: where the lens was against the body (`CameraHeightLevel.rawValue`).
    var heightLevel: String? = nil
    /// standing / leaning / sitting
    var posture: String? = nil
    /// Where the subject faces, seen from the camera: front / left / right / back.
    var facing: String? = nil
    /// The shot size actually taken (`PresetAnalysis.ShotSize.rawValue`).
    var shot: String? = nil
    var note: String = ""
    /// Photographer closed the form without entering anything.
    var skipped = false
    /// Shot size the guide was on at the shutter (filled by the app, for comparison).
    var guideShot: String? = nil

    /// Lens above the eyes, cm (+ = camera above the eyes, same sign as the guide's vantage).
    var cameraVsEyesCm: Double? {
        guard let c = cameraHeightCm, let e = eyeHeightCm else { return nil }
        return c - e
    }
}
