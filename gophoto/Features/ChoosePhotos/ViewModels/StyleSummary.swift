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

    /// Share of photos at or above which a trait counts as the user's, and "Always".
    static let clearShare = 0.70
    static let alwaysShare = 0.90

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
                let copy = Self.shotCopy(first)
                traits.append(Trait(symbol: Self.shotSymbol(first),
                                    title: share >= Self.alwaysShare ? Self.always(copy.title) : copy.title,
                                    line: copy.line, evidence: "\(k) of \(n) photos"))
            } else if ranked.count >= 2,
                      Double(k + counts[ranked[1]]!) / Double(n) >= Self.clearShare {
                top = first
                wide = first == .full || first == .threeQuarter
                let both = Self.shotName(first) + " or " + Self.shotName(ranked[1]).lowercased()
                traits.append(Trait(symbol: "rectangle.on.rectangle", title: both,
                                    line: "You switch between the two. Pick one when you shoot.",
                                    evidence: "\(k + counts[ranked[1]]!) of \(n) photos"))
            }
        }

        // 2. Camera height against the eyes.
        enum Angle { case below, above, neutral }
        var angle = Angle.neutral
        let side = analysis.eyeSide.flatMap(PresetAnalysis.EyeSide.init(rawValue:))
        let source = analysis.eyeSideSource.flatMap(PresetAnalysis.EyeSideSource.init(rawValue:))
        if let side, source == .taste {
            angle = side == .below ? .below : .above
            let n = analysis.eyeSidePhotoCount ?? 0
            let share = side == .above ? (analysis.eyeAboveShare ?? 1) : 1 - (analysis.eyeAboveShare ?? 0)
            let k = Int((share * Double(n)).rounded())
            let title = side == .below ? "From slightly below" : "From slightly above"
            traits.append(Trait(symbol: side == .below ? "arrow.up.circle" : "arrow.down.circle",
                                title: share >= Self.alwaysShare ? Self.always(title) : title,
                                line: side == .below ? "It makes you look taller." : "It feels soft and close.",
                                evidence: n > 0 ? "\(k) of \(n) photos" : nil))
        } else if source == .mixed {
            traits.append(Trait(symbol: "arrow.up.and.down.circle", title: "No fixed angle",
                                line: "Your angles vary, so we'll use a classic one for each shot.",
                                evidence: nil))
        } else {
            traits.append(Trait(symbol: "sparkles", title: "Still learning your angle",
                                line: "Add a few more photos and we'll find it.", evidence: nil))
        }

        // 3. Where they stand (median position over the photos).
        var offSide = false
        if let box = analysis.subjectBox, analysis.subjectPhotoCount > 0 {
            let x = box.midX
            offSide = x < 0.4 || x > 0.6
            traits.append(offSide
                ? Trait(symbol: x < 0.5 ? "align.horizontal.left" : "align.horizontal.right",
                        title: "Off to the side", line: "You leave room for the view.", evidence: nil)
                : Trait(symbol: "align.horizontal.center", title: "Center stage",
                        line: "You stand right in the middle.", evidence: nil))
        }

        // Style name: shot (wide / close) × angle × position.
        let persona: (String, String)?
        switch (wide, angle, offSide) {
        case (true?, .below, true):    persona = ("The Explorer", "Big places, all of you, room for the view.")
        case (true?, .below, false):   persona = ("The Main Character", "Center stage, head to toe, standing tall.")
        case (true?, _, true):         persona = ("The Wanderer", "You and the place, side by side.")
        case (true?, _, false):        persona = ("The Classic", "Clean, centered, timeless.")
        case (false?, .above, false):  persona = ("The Portrait Lover", "Close, soft, and all about your face.")
        case (false?, .above, true):   persona = ("The Daydreamer", "Close up, off to the side, a little dreamy.")
        case (false?, _, false):       persona = ("The Icon", "Up close and confident.")
        case (false?, _, true):        persona = ("The Storyteller", "Close enough to feel, wide enough to tell where.")
        case (nil, _, _):              persona = nil
        }

        let ordered = zip(photos, shots).sorted { a, b in (a.1 == top ? 0 : 1) < (b.1 == top ? 0 : 1) }
        self.name = persona?.0
        self.tagline = persona?.1
        self.traits = Array(traits.prefix(3))
        self.photoCount = photos.count
        self.highlights = ordered.prefix(3).map { $0.0.image }
    }

    // MARK: Copy

    private static func shotCopy(_ shot: PresetAnalysis.ShotSize) -> (title: String, line: String) {
        switch shot {
        case .full:         ("Head to toe", "You like the whole you in the frame.")
        case .threeQuarter: ("Knees up", "Enough to show the outfit, close enough to see your face.")
        case .half:         ("Waist up", "You keep it personal, with a bit of the place around you.")
        case .quarter:      ("Up close", "Your face does the talking.")
        }
    }

    private static func shotName(_ shot: PresetAnalysis.ShotSize) -> String {
        switch shot {
        case .full: "Full body"
        case .threeQuarter: "Knees up"
        case .half: "Waist up"
        case .quarter: "Up close"
        }
    }

    private static func shotSymbol(_ shot: PresetAnalysis.ShotSize) -> String {
        switch shot {
        case .full, .threeQuarter: "figure.stand"
        case .half: "person.crop.square"
        case .quarter: "person.crop.circle"
        }
    }

    /// "Head to toe" → "Always head to toe".
    private static func always(_ title: String) -> String {
        "Always " + title.prefix(1).lowercased() + title.dropFirst()
    }
}
