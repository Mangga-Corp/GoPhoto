//
//  StyleSummary.swift
//  gophoto
//
//  The "Your style" card's content, made from a preset's analysis: a style name, up to three
//  traits with how many photos show them, and the photos that show the style best.
//  It only says what the photos clearly show: a trait most photos don't share is called mixed
//  or left out ("better no claim than a wrong one").
//

import UIKit

struct StyleSummary {
    struct Trait {
        let symbol: String
        let title: String
        let line: String
        /// "9 of 12 photos", or nil when there is no clear count.
        let evidence: String?
    }

    /// Style name ("The Explorer"), or nil when the shot size is not clear.
    let name: String?
    let tagline: String?
    let traits: [Trait]
    let photoCount: Int
    /// Up to three photos of the most common shot size.
    let highlights: [UIImage]

    /// Share of photos at or above which a trait counts as the user's.
    static let clearShare = 0.70

    init?(analysis: PresetAnalysis?, photos: [PhotoItem]) {
        guard let analysis, !photos.isEmpty else { return nil }
        typealias Shot = PresetAnalysis.ShotSize
        var traits: [Trait] = []

        // 1. Shot size.
        let shots = photos.map { photo in
            analysis.photoShotSizes?[photo.id.uuidString].flatMap(Shot.init(rawValue:))
        }
        let known = shots.compactMap { $0 }
        var counts: [Shot: Int] = [:]
        for shot in known { counts[shot, default: 0] += 1 }
        let ranked = Shot.allCases.filter { counts[$0] != nil }.sorted { a, b in
            counts[a]! != counts[b]! ? counts[a]! > counts[b]!
                : Shot.allCases.firstIndex(of: a)! < Shot.allCases.firstIndex(of: b)!
        }
        var top: Shot?
        var wide: Bool?
        if let first = ranked.first {
            let n = known.count, k = counts[first]!
            let share = Double(k) / Double(n)
            if share >= Self.clearShare {
                top = first
                wide = first == .full || first == .threeQuarter
                if first == .full {
                    traits.append(Trait(
                        symbol: "figure.stand",
                        title: "Full-body shots",
                        line: "Keep your whole look in the photo.",
                        evidence: "\(k) of \(n) photos"
                    ))
                }
            } else if ranked.count >= 2,
                      Double(k + counts[ranked[1]]!) / Double(n) >= Self.clearShare {
                top = first
                wide = first == .full || first == .threeQuarter
            }
        }

        // 2. Camera height against the eyes.
        enum Angle { case below, above, neutral }
        var angle = Angle.neutral
        let side = analysis.eyeSide.flatMap(PresetAnalysis.EyeSide.init(rawValue:))
        let source = analysis.eyeSideSource.flatMap(PresetAnalysis.EyeSideSource.init(rawValue:))
        if let side, source == .taste {
            angle = side == .below ? .below : .above
        }
        traits.append(Trait(
            symbol: "arrow.up.and.down.circle",
            title: "Easy Angles",
            line: "We'll find the best angle for you.",
            evidence: nil
        ))

        // 3. Where they stand (median position over the photos).
        let offSide: Bool?
        if let box = analysis.subjectBox, analysis.subjectPhotoCount > 0 {
            let x = box.midX
            offSide = x < 0.4 || x > 0.6
            if x >= 0.4 && x <= 0.6 {
                traits.append(Trait(
                    symbol: "align.horizontal.center",
                    title: "Centered",
                    line: "Stand naturally in the middle of the photo.",
                    evidence: nil
                ))
            }
        } else {
            offSide = nil
        }

        // Style name: shot (wide / close) × angle × position.
        let persona: (String, String)?
        if let wide, let offSide {
            switch (wide, angle, offSide) {
            case (true, .below, true):    persona = ("The Explorer", "Big places, all of you, room for the view.")
            case (true, .below, false):   persona = ("The Main Character", "Center stage, head to toe, standing tall.")
            case (true, _, true):         persona = ("The Wanderer", "You and the place, side by side.")
            case (true, _, false):        persona = ("The Classic", "Clean, centered, timeless.")
            case (false, .above, false):  persona = ("The Portrait Lover", "Close, soft, and all about your face.")
            case (false, .above, true):   persona = ("The Daydreamer", "Close up, off to the side, a little dreamy.")
            case (false, _, false):       persona = ("The Icon", "Up close and confident.")
            case (false, _, true):        persona = ("The Storyteller", "Close enough to feel, wide enough to tell where.")
            }
        } else {
            persona = nil
        }

        let ordered = zip(photos, shots).sorted { a, b in (a.1 == top ? 0 : 1) < (b.1 == top ? 0 : 1) }
        self.name = persona?.0
        self.tagline = persona?.1
        self.traits = Array(traits.prefix(3))
        self.photoCount = photos.count
        self.highlights = ordered.prefix(3).map { $0.0.image }
    }

    // MARK: Copy

}
