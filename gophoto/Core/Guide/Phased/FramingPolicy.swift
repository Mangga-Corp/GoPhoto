//
//  FramingPolicy.swift
//  gophoto
//
//  How the Phased guide finishes the framing (Auto crop / No crop). Moved here from
//  `Core/Guide/Experiment/ExperimentMode.swift` on 13 Nov when the developer experiment code moved to
//  the debugphoto repo: the Phased engine needs this type in production.
//
import Foundation

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
            "No crop after the shot: the saved photo is what the camera framed. Zoom is only 1× or 2× (lens / sensor crop), chosen before the distance phase. Left/right is guided in the final framing."
        }
    }

    static func saved(_ defaults: UserDefaults = .standard) -> FramingPolicy {
        defaults.string(forKey: storageKey).flatMap(FramingPolicy.init(rawValue:)) ?? .autoCrop
    }
}
