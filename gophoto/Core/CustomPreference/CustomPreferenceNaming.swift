//
//  CustomPreferenceNaming.swift
//  gophoto
//
//  The preference name for every subject placement × camera angle combination, so a custom
//  preference has a meaningful name in the preference list without the user typing one.
//

import Foundation

nonisolated enum CustomPreferenceNaming {

    /// A hand-picked name for each combination. Every name is distinct.
    static func name(for style: CustomPreferenceStyle) -> String {
        switch (style.placement, style.angle) {
        case (.ruleOfThirds, .eyeLevel): "Balanced Thirds Portrait"
        case (.ruleOfThirds, .lowAngle): "Heroic Thirds"
        case (.ruleOfThirds, .highAngle): "Gentle Thirds From Above"

        case (.central, .eyeLevel): "Classic Centered Portrait"
        case (.central, .lowAngle): "Powerful Center Stage"
        case (.central, .highAngle): "Soft Centered Look-Down"

        case (.offCentered, .eyeLevel): "Natural Off-Center"
        case (.offCentered, .lowAngle): "Confident Off-Center"
        case (.offCentered, .highAngle): "Candid Off-Center From Above"

        case (.edgeProximity, .eyeLevel): "Quiet Edge Portrait"
        case (.edgeProximity, .lowAngle): "Bold Edge Hero"
        case (.edgeProximity, .highAngle): "Lonely Edge From Above"

        case (.rightSide, .eyeLevel): "Right-Side Story"
        case (.rightSide, .lowAngle): "Right-Side Hero"
        case (.rightSide, .highAngle): "Right-Side Look-Down"

        case (.leftSide, .eyeLevel): "Left-Side Focus"
        case (.leftSide, .lowAngle): "Left-Side Hero"
        case (.leftSide, .highAngle): "Left-Side Look-Down"

        case (.edgeTouching, .eyeLevel): "Raw Cropped Edge"
        case (.edgeTouching, .lowAngle): "Looming Cropped Edge"
        case (.edgeTouching, .highAngle): "Fragmented Look-Down"
        }
    }

    /// `base` when no saved preference uses it, else "base 2", "base 3", … (names are compared
    /// case-insensitively, like the existing name validation).
    static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }
}
