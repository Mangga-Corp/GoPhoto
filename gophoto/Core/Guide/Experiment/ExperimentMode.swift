//
//  ExperimentMode.swift
//  gophoto
//
//  appMode 2 (developer) guide experiment: which guide runs and how the final framing is done.
//  appMode 1 always runs Phased · Auto crop (since 9 Nov; before: `mainModified`) and never reads these settings.
//  Spec: Docs/Experiments/PhaseGuide/Spec-v3.md
//
import Foundation

/// The guide under test (appMode 2). Not the app mode.
nonisolated enum ExperimentGuide: String, CaseIterable, Identifiable, Sendable, Codable {
    /// The team's guide from `main` @ a68494f (B + crop), frozen in `Core/Guide/Legacy`.
    case main
    /// Reynard's tuned B + crop (appMode 1 until 9 Nov; now Phased · Auto crop there).
    case mainModified
    /// New phase-by-phase guide.
    case phased
    /// Phased + native depth as extra evidence (dual-wide camera, 12 MP photos).
    case phasedDepth

    static let storageKey = "experimentGuide"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .main:         "Main"
        case .mainModified: "Main modified"
        case .phased:       "Phased"
        case .phasedDepth:  "Phased + Depth"
        }
    }

    /// The phase-based family (framing policy applies).
    var isPhased: Bool { self == .phased || self == .phasedDepth }
    var usesDepth: Bool { self == .phasedDepth }

    var summary: String {
        switch self {
        case .main:
            "The team's original guide (B + crop, main @ a68494f). Steps: distance → phone height → tilt → left/right, auto zoom 1–2×. Targets come from the current analysis (v18)."
        case .mainModified:
            "The tuned B + crop (the tester build's guide until 9 Nov): body-cut check, zoom waits its turn, steps count after 0.4 s, phone height in face units."
        case .phased:
            "New guide, one phase at a time: distance (with room) → phone height → tilt → final framing. Distance stays done unless the photo really can't work. One instruction, no ticks; \"Take the photo now\" when everything is valid."
        case .phasedDepth:
            "Same phases as Phased, plus Apple depth from the dual camera as extra evidence that the distance really changed. Photos are about 12 MP."
        }
    }

    static func saved(_ defaults: UserDefaults = .standard) -> ExperimentGuide {
        defaults.string(forKey: storageKey).flatMap(ExperimentGuide.init(rawValue:)) ?? .mainModified
    }
}

/// How the Phased guides finish the framing (ignored by Main / Main modified).
nonisolated enum FramingPolicy: String, CaseIterable, Identifiable, Sendable, Codable {
    case autoCrop
    case noCrop

    static let storageKey = "experimentFraming"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoCrop: "Auto crop"
        case .noCrop:   "No crop"
        }
    }

    var summary: String {
        switch self {
        case .autoCrop:
            "Shoots at the largest size at 1× and crops only when needed, never below the quality floor (12 MP; 8 MP with depth). The crop is not drawn: the pill turns green when ready. A photo taken before that is cropped with what is valid at that moment. The original is saved too."
        case .noCrop:
            "No crop after the shot. Zoom is only 1× or 2× (lens / sensor crop), chosen before the distance phase. Small framing differences are accepted."
        }
    }

    static func saved(_ defaults: UserDefaults = .standard) -> FramingPolicy {
        defaults.string(forKey: storageKey).flatMap(FramingPolicy.init(rawValue:)) ?? .autoCrop
    }
}

/// The guide + framing a frame or a capture belongs to (logs compare the combinations).
nonisolated struct ExperimentSelection: Equatable, Sendable, Codable {
    var guide: ExperimentGuide
    var framing: FramingPolicy

    /// Framing only exists for the Phased family.
    var label: String { guide.isPhased ? "\(guide.title) · \(framing.title)" : guide.title }
    var framingLabel: String? { guide.isPhased ? framing.rawValue : nil }
}
