//
//  LensRecommendationLogging.swift
//  gophoto
//
//  Diagnostic logging helper for lens recommendations.
//

import Foundation
import AVFoundation

enum LensRecommendationLog {
    private static let prefix = "[LensRecommendation]"

    static func timestamp() -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: now)
    }

    private static func deviceTypeString(_ type: AVCaptureDevice.DeviceType) -> String {
        switch type {
        case .builtInWideAngleCamera: return "wide"
        case .builtInTelephotoCamera: return "telephoto"
        case .builtInDualCamera: return "dual"
        case .builtInDualWideCamera: return "dualWide"
        case .builtInTripleCamera: return "triple"
        case .builtInUltraWideCamera: return "ultraWide"
        default: return String(describing: type)
        }
    }

    static func evaluation(
        zoom: Double,
        minZoom: Double,
        maxZoom: Double,
        iso: Float?,
        exposureDuration: Double?,
        exposureTargetOffset: Float?,
        activeCamera: AVCaptureDevice.DeviceType?,
        personDetected: Bool,
        clipped: Bool,
        lowLight: Bool?,
        telephotoEligible: Bool,
        recommendation: String?,
        reason: String
    ) {
        let isoStr = iso.map { String(format: "%.0f", $0) } ?? "unknown"
        let durStr = exposureDuration.map { String(format: "%.3f", $0) } ?? "unknown"
        let offsetStr = exposureTargetOffset.map { String(format: "%.1f", $0) } ?? "unknown"
        let cameraStr = activeCamera.map { deviceTypeString($0) } ?? "unknown"
        let lowLightStr = lowLight.map { "\($0)" } ?? "unknown"
        print("\(prefix)[EVALUATION] timestamp=\(timestamp()) zoom=\(String(format: "%.2f", zoom)) minZoom=\(String(format: "%.2f", minZoom)) maxZoom=\(String(format: "%.2f", maxZoom)) iso=\(isoStr) exposureDuration=\(durStr) exposureTargetOffset=\(offsetStr) activeCamera=\(cameraStr) personDetected=\(personDetected) clipped=\(clipped) lowLight=\(lowLightStr) telephotoEligible=\(telephotoEligible) recommendation=\(recommendation ?? "none") reason=\(reason)")
    }

    static func decision(
        recommendation: String,
        autoApply: Bool,
        reason: String,
        evidence: [String]
    ) {
        print("\(prefix)[DECISION] recommendation=\(recommendation) autoApply=\(autoApply) reason=\(reason) evidence=\(evidence.joined(separator: ","))")
    }

    static func cooldownSuppressed(remaining: TimeInterval, evidenceChanged: Bool) {
        print("\(prefix)[COOLDOWN] suppressed remaining=\(String(format: "%.1f", remaining))s evidenceChanged=\(evidenceChanged)")
    }

    static func filter(action: String, reason: String, evidence: String) {
        print("\(prefix)[FILTER] action=\(action) reason=\(reason) evidence=\(evidence)")
    }

    static func card(action: String, recommendation: String?) {
        print("\(prefix)[CARD] action=\(action) recommendation=\(recommendation ?? "none")")
    }

    static func apply(phase: String, source: String, requestedZoom: Double, currentZoom: Double, appliedZoom: Double, activeCamera: String, error: String?) {
        let errorStr = error.map { " error=\($0)" } ?? ""
        print("\(prefix)[APPLY] phase=\(phase) source=\(source) requestedZoom=\(String(format: "%.2f", requestedZoom)) currentZoom=\(String(format: "%.2f", currentZoom)) appliedZoom=\(String(format: "%.2f", appliedZoom)) activeCamera=\(activeCamera)\(errorStr)")
    }

    /// Automatic zoom diagnostics (continuous 0.5× – 3.0×). Logged on changes only.
    static func auto(_ event: String, _ detail: String) {
        print("[AutoLens] \(timestamp()) event=\(event) \(detail)")
    }

    /// Detailed decision diagnostics for automatic zoom. Logged when the smoothed target changes
    /// or when a significant decision transition occurs (not every frame).
    static func autoDecision(
        currentZoom: Double,
        rawTarget: Double,
        smoothedTarget: Double,
        requestedTarget: Double,
        personBoxHeight: Double?,
        preferredSubjectHeight: Double?,
        framingRatio: Double?,
        clutterSummary: String?,
        environmentProminence: String?,
        preferredObjectShare: Double?,
        confidence: Double,
        direction: String,
        reason: String
    ) {
        let personStr = personBoxHeight.map { String(format: "%.3f", $0) } ?? "none"
        let preferredStr = preferredSubjectHeight.map { String(format: "%.3f", $0) } ?? "none"
        let ratioStr = framingRatio.map { String(format: "%.2f", $0) } ?? "none"
        let clutterStr = clutterSummary ?? "none"
        let prominenceStr = environmentProminence ?? "unknown"
        let objectStr = preferredObjectShare.map { String(format: "%.2f", $0) } ?? "unknown"
        print(
            "[AutoLens] \(timestamp()) [DECISION] current=\(String(format: "%.2f", currentZoom)) "
            + "raw=\(String(format: "%.2f", rawTarget)) smoothed=\(String(format: "%.2f", smoothedTarget)) "
            + "requested=\(String(format: "%.2f", requestedTarget)) "
            + "personHeight=\(personStr) preferredHeight=\(preferredStr) ratio=\(ratioStr) "
            + "clutter=\(clutterStr) prominence=\(prominenceStr) preferredObjects=\(objectStr) "
            + "confidence=\(String(format: "%.2f", confidence)) direction=\(direction) reason=\(reason)"
        )
    }

    /// Zoom application lifecycle log. Use a shared `transitionId` to correlate the decision,
    /// request, and completion logs for one automatic adjustment.
    static func autoLifecycle(
        transitionId: String,
        phase: String,         // "decision" | "requested" | "completed" | "failed"
        currentZoom: Double,
        targetZoom: Double,
        requestedZoom: Double,
        appliedZoom: Double,
        direction: String,
        confidence: Double,
        activeCamera: String,
        reason: String? = nil,
        error: String? = nil
    ) {
        let reasonStr = reason.map { " reason=\($0)" } ?? ""
        let errorStr = error.map { " error=\($0)" } ?? ""
        print(
            "[AutoLens] \(timestamp()) [LIFECYCLE] id=\(transitionId) phase=\(phase) "
            + "current=\(String(format: "%.2f", currentZoom)) target=\(String(format: "%.2f", targetZoom)) "
            + "requested=\(String(format: "%.2f", requestedZoom)) applied=\(String(format: "%.2f", appliedZoom)) "
            + "direction=\(direction) confidence=\(String(format: "%.2f", confidence)) "
            + "camera=\(activeCamera)\(reasonStr)\(errorStr)"
        )
    }

    static func error(_ message: String) {
        print("\(prefix)[ERROR] \(message)")
    }
}
