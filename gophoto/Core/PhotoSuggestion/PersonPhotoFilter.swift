//
//  PersonPhotoFilter.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//

import CoreGraphics
import Foundation

nonisolated struct PersonPhoto: Identifiable, Equatable, Sendable {
    let id: String
    let presence: PersonPresence
    let thumbnailURL: URL?
    /// The chosen person's face in this photo, normalized, origin top-left.
    let faceBounds: CGRect?
}

nonisolated enum PersonPresence: Equatable, Sendable {
    /// Only this person has a visible face.
    case solo
    /// Other faces exist, but all are small next to this person's.
    case mainFocus
    /// Someone else is about as prominent.
    case group
    case absent
}

nonisolated enum PersonPhotoFilter {
    /// Faces shorter than this share of the image height are background and ignored.
    static let minimumFaceHeight = 0.03
    /// Another face at or above this share of the chosen face's area makes it a group photo
    /// (same ratio the analysis uses in SubjectSelector.ambiguityRatio).
    static let mainFocusRatio = SubjectSelector.ambiguityRatio

    static func presence(of entityID: String, in faces: [PersonFace]) -> PersonPresence {
        let visible = faces.filter { Double($0.bounds.height) >= minimumFaceHeight }
        guard let chosen = visible.filter({ $0.entityID == entityID }).max(by: { $0.area < $1.area }) else {
            return .absent
        }
        let largestOther = visible.filter { $0.entityID != entityID }.map(\.area).max()
        guard let largestOther else { return .solo }
        return largestOther < chosen.area * mainFocusRatio ? .mainFocus : .group
    }

    static func isIncluded(_ presence: PersonPresence) -> Bool {
        presence == .solo || presence == .mainFocus
    }

    /// Presence of the person in every scanned photo that has at least one face.
    static func presences(of entityID: String, in facesByAsset: [String: [PersonFace]]) -> [String: PersonPresence] {
        facesByAsset.mapValues { presence(of: entityID, in: $0) }
    }
}
