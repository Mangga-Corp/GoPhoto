//
//  LensCapability.swift
//  gophoto
//
//  Camera capability model for lens recommendations.
//

import AVFoundation
import UIKit

/// Supported lens recommendation option.
enum LensOption: Equatable, Sendable {
    case ultrawide(Double)   // e.g. 0.5×
    case wide                 // 1×

    var title: String {
        switch self {
        case .ultrawide(let factor): return "Try \(String(format: "%.1f", factor))× ultrawide"
        case .wide: return "Use the wide view"
        }
    }

    var zoomFactor: Double {
        switch self {
        case .ultrawide(let f): return f
        case .wide: return 1.0
        }
    }
}

/// What the app knows about the current camera's zoom and lens capabilities.
struct LensCapabilities: Equatable, Sendable {
    let minZoom: Double
    let maxZoom: Double
    let currentZoom: Double
    let deviceType: AVCaptureDevice.DeviceType
    /// Switch-over zoom factors, if available (approximate optical breakpoints).
    let opticalBreakpoints: [Double]

    /// Whether the device can reasonably act as an ultrawide (zoom < 1.0 or virtual dual-wide).
    var supportsUltrawide: Bool {
        minZoom < 1.0 || deviceType == .builtInDualWideCamera || deviceType == .builtInTripleCamera
    }

    /// Best supported ultrawide zoom, clamped to actual min.
    var bestUltrawide: Double? {
        guard supportsUltrawide else { return nil }
        let candidates = [0.5, minZoom]
        return candidates.filter { $0 >= minZoom - 0.001 && $0 < 1.0 }.first
    }

    static func from(
        _ device: AVCaptureDevice,
        currentUserZoom: Double,
        userMin: Double,
        userMax: Double
    ) -> LensCapabilities {
        let nsBreakpoints = device.virtualDeviceSwitchOverVideoZoomFactors ?? []
        let breakpoints = nsBreakpoints.compactMap { $0 as? Double }
        return LensCapabilities(
            minZoom: userMin,
            maxZoom: userMax,
            currentZoom: currentUserZoom,
            deviceType: device.deviceType,
            opticalBreakpoints: breakpoints
        )
    }
}

/// Exposure snapshot for low-light evaluation.
struct ExposureSnapshot: Equatable, Sendable {
    let iso: Float
    let exposureDuration: Double
    let exposureTargetOffset: Float

    /// Heuristic low-light flag. This is conservative: missing data returns nil.
    var isLikelyLowLight: Bool? {
        guard iso > 0, exposureDuration > 0 else { return nil }
        // High ISO + slow shutter + underexposed target → likely low light.
        // Thresholds are product heuristics, not hardware guarantees.
        let highISO = iso > 800
        let slowShutter = exposureDuration > 1.0 / 30.0
        let underexposed = exposureTargetOffset < -0.5
        return (highISO || slowShutter) && underexposed
    }
}
