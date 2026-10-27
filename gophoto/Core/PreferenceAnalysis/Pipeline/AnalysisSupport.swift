import Foundation

// MARK: - Which evidence a scan collects

/// GoPhoto reads the camera angle with GeoCalib, so the evidence only the older
/// angle method used (3D body pose, background vertical lines) is not collected.
nonisolated struct EvidenceOptions: Sendable, Equatable {
    /// Vision 3D body pose. Used only by the older angle method.
    var bodyPose3D = true
    /// Background vertical line detection. Used only by the older angle method.
    var verticalLines = true

    static let all = EvidenceOptions()

    init() {}

    init(angleMode: CameraAngleMethod) {
        let original = angleMode == .original
        bodyPose3D = original
        verticalLines = original
    }
}

// MARK: - Per-photo timing

/// Where one photo's analysis time went, in milliseconds (for logs and debugging).
nonisolated struct PhotoScanTiming: Sendable, Equatable, Codable {
    var prepareMs: Double
    var evidenceMs: Double
    var interpretMs: Double
    var angleModelMs: Double
    var geoCalibPreprocessMs: Double?
    var geoCalibPredictMs: Double?
    var geoCalibOptimizeMs: Double?

    var totalMs: Double { prepareMs + evidenceMs + interpretMs + angleModelMs }
}
