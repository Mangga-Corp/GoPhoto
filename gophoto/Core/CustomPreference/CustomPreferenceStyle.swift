//
//  CustomPreferenceStyle.swift
//  gophoto
//
//  A preference built from two choices instead of reference photos: where the subject sits in
//  the frame and the camera angle. Saved with the preference; the camera targets are derived
//  from it by `CustomPresetAnalysisFactory`, never stored separately.
//

import Foundation

/// One choice on a custom preference page (subject placement or camera angle).
nonisolated protocol CustomStyleOption: Identifiable, Hashable, CaseIterable, Sendable
where AllCases == [Self] {
    /// The choice's name, e.g. "Rule of Thirds".
    var title: String { get }
    /// What the choice means for the photo.
    var summary: String { get }
    /// Optional photo in the asset catalog. When it is missing the card draws an illustration.
    var photoAssetName: String { get }
}

// MARK: - Subject placement

nonisolated enum SubjectPlacement: String, Codable, CustomStyleOption {
    case ruleOfThirds
    case central
    case offCentered
    case edgeProximity
    case rightSide
    case leftSide
    case edgeTouching

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ruleOfThirds: "Rule of Thirds"
        case .central: "Central Placement"
        case .offCentered: "Off-Centered Placement"
        case .edgeProximity: "Edge Proximity / Near the Edge"
        case .rightSide: "Right Side Composition"
        case .leftSide: "Left Side Composition"
        case .edgeTouching: "Edge/Corner Touching"
        }
    }

    var summary: String {
        switch self {
        case .ruleOfThirds:
            "Divides the frame into 9 boxes with 4 lines and their intersection points. The subject is placed on one or two of those intersections to create a dynamic, balanced composition."
        case .central:
            "The subject is placed right in the center of the frame. This gives a stable, symmetrical, formal and strong feel (great for architecture, reflections or straight-on face portraits)."
        case .offCentered:
            "The subject is shifted slightly away from the dead center to make the image feel more natural and pleasing to look at."
        case .edgeProximity:
            "Places the subject close to the border or corner of the frame to create visual tension and emphasize the empty space around it."
        case .rightSide:
            "Feels in tune with the natural reading direction (left to right), often paired with negative space on the left."
        case .leftSide:
            "Holds back the natural flow of the eye to grab attention right away or create implied movement."
        case .edgeTouching:
            "The subject sits too close to, or is cut off by, the edge of the frame. This often creates unintended or distracting tension."
        }
    }

    /// Short label for preference card chips.
    var shortTitle: String {
        switch self {
        case .ruleOfThirds: "Rule of Thirds"
        case .central: "Center"
        case .offCentered: "Off-Center"
        case .edgeProximity: "Near the Edge"
        case .rightSide: "Right Side"
        case .leftSide: "Left Side"
        case .edgeTouching: "Edge Touching"
        }
    }

    var photoAssetName: String { "CustomPlacement-\(rawValue)" }
}

// MARK: - Camera angle

nonisolated enum CameraAngleStyle: String, Codable, CustomStyleOption {
    case eyeLevel
    case lowAngle
    case highAngle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .eyeLevel: "Eye Level"
        case .lowAngle: "Low Angle"
        case .highAngle: "High Angle"
        }
    }

    var summary: String {
        switch self {
        case .eyeLevel:
            "The camera is positioned level with the subject's eyes for a natural, equal point of view. Great for portraits, human interest and documentary photos."
        case .lowAngle:
            "The camera is placed lower than the subject and pointed upward. This makes the subject look taller, stronger, grander or more dominant."
        case .highAngle:
            "The camera is higher than the subject and pointed downward. This makes the subject look smaller, weaker or more vulnerable, or puts the focus on the surroundings."
        }
    }

    /// Short label for preference card chips.
    var shortTitle: String {
        switch self {
        case .eyeLevel: "Eye Level"
        case .lowAngle: "Low"
        case .highAngle: "High"
        }
    }

    var photoAssetName: String { "CustomAngle-\(rawValue)" }
}

// MARK: - Style

nonisolated struct CustomPreferenceStyle: Codable, Hashable, Sendable {
    let placement: SubjectPlacement
    let angle: CameraAngleStyle

    /// The preference name suggested for this combination (unique per combination).
    var suggestedName: String { CustomPreferenceNaming.name(for: self) }
}
