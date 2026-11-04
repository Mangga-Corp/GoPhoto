//
//  SceneIdeasEngine.swift
//  gophoto
//
//  Place ideas with Apple Foundation Models (on-device). Ported from the GoPhotoNIMA prototype:
//  prompt V00 (unchanged after sampling + blind confirmation), role guard v2, person guide v1.2,
//  InputCheck v1 (soft block). Foundation only names visible elements and picks a role from a
//  fixed list; every sentence the user reads comes from app templates.
//

import Foundation
import CoreGraphics
import ImageIO
import FoundationModels

// MARK: - Model output schema (order = generation order)

@Generable nonisolated enum FMSceneRole {
    case landmark, leadingLine, frame, plainBackdrop, pattern, lightOrReflection, distraction, none
}

@Generable nonisolated struct FMSceneElement {
    @Guide(description: "What you see, 2 to 6 words.")
    var description: String
    var role: FMSceneRole
    @Guide(description: "The part of it that matters most for the photo, 2 to 6 words.")
    var part: String
}

@Generable nonisolated struct FMSceneSurvey {
    @Guide(description: "Max 20 words: the main things you see, plain words.")
    var observation: String
    @Guide(description: "True for any normal photo of a place. False only for a plain color, an extremely blurry or an almost black image.")
    var usable: Bool
    @Guide(description: "Visual things you can really see that could matter in a photo of a person here, the most important first.", .maximumCount(5))
    var elements: [FMSceneElement]
}

// MARK: - Results

nonisolated struct SceneIdea: Identifiable, Equatable, Sendable {
    let id: Int
    let element: String
    let role: String
    let why: String
    let keep: String
    var part: String = ""
    /// Shown because the role guard removed an earlier idea.
    var replacement = false
}

nonisolated struct SceneIdeasResult: Equatable, Sendable {
    let ideas: [SceneIdea]
    let warnings: [String]
    let observation: String
    let raw: [String]
    let seconds: Double
}

// MARK: - Advisor (one run, temperature 0.7)

nonisolated enum SceneIdeaAdvisor {
    /// Prompt V00 (GoPhotoNIMA `SurveyAdvisor.instructionsRoles`). Do not edit without a new test.
    static let instructions = """
    You help a traveler see what in a place could matter for a photo of them. \
    The image shows the place. Nobody is in it yet.

    Work in order:
    1. Look at the place and write what you see.
    2. List the visual things that could matter in a photo of a person here, the most important first. \
    Give each one a role:
    - landmark: a distinctive building or object that shows where this is.
    - leadingLine: a line, edge or curve that leads the eye through the picture.
    - frame: something at the edges that surrounds the scene.
    - plainBackdrop: a calm, clean surface with little detail.
    - pattern: repeating shapes or texture.
    - lightOrReflection: lamps, glow, bright light or reflections.
    - distraction: a bright or busy small thing that would pull attention away from a person.
    - none: none of these.
    For each thing, also name the part of it that matters most.

    Rules:
    - Only mention things you can actually see. Never name places or brands.
    - Do not give poses, standing spots or camera settings.
    - Write short, plain English. No idioms, no numbers.
    """

    static var unavailableReason: String? {
        guard case .unavailable(let reason) = SystemLanguageModel.default.availability else { return nil }
        switch reason {
        case .deviceNotEligible: return "Photo ideas need Apple Intelligence, which this iPhone doesn't support."
        case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings → Apple Intelligence & Siri to get photo ideas."
        case .modelNotReady: return "Apple Intelligence is still getting ready. Try again in a few minutes."
        @unknown default: return "Apple Intelligence isn't available right now."
        }
    }

    static func describe(_ error: Error) -> String {
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation: return "Couldn't make ideas for this view. Try another angle."
            case .assetsUnavailable: return "Apple Intelligence is still getting ready. Try again later."
            case .rateLimited: return "Too many requests. Wait a moment and try again."
            default: break
            }
        }
        return "Couldn't make ideas right now. Try again."
    }

    /// One run → guard → two ideas with template sentences.
    static func run(_ image: CGImage) async throws -> SceneIdeasResult {
        let t0 = Date()
        let session = LanguageModelSession(instructions: instructions)
        let survey = try await session.respond(generating: FMSceneSurvey.self, options: GenerationOptions(temperature: 0.7)) {
            "Look at this place and list what could matter for a photo of a person here."
            Attachment(image)
        }.content
        let els = survey.elements.map { e in (desc: e.description, role: "\(e.role)", part: e.part) }
        let warnings = els.filter { $0.role == "distraction" }.map { SceneText.clean($0.desc) }
        let usable = els.filter { !["distraction", "none"].contains($0.role) }
        let unguarded = Array(usable.prefix(2))
        let chosen = Array(usable.filter { !SceneRoleGuard.isBlocked($0.desc, role: $0.role) }.prefix(2))
        let ideas = chosen.enumerated().map { k, e -> SceneIdea in
            let t = SceneText.whyKeep(desc: e.desc, role: e.role, part: e.part, warnings: warnings)
            return SceneIdea(id: k, element: e.desc, role: e.role, why: t.why, keep: t.keep, part: e.part,
                             replacement: !unguarded.contains { $0.desc == e.desc && $0.role == e.role })
        }
        let raw = els.map { "\($0.desc) [\($0.role)] · \($0.part)" }
        return SceneIdeasResult(ideas: ideas, warnings: warnings, observation: survey.observation, raw: raw,
                                seconds: Date().timeIntervalSince(t0))
    }
}

// MARK: - Text helpers + "why / keep" templates

nonisolated enum SceneText {
    static let preps = [" with ", " of ", " on ", " in ", " near ", " at ", " along ", " above ", " below ", " under ", " behind ",
                        " running ", " leading ", " through ", " across ", " around ", " over ", " from ", " for "]
    static func clean(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let l = s.last, ".!,;".contains(l) { s.removeLast() }
        for a in ["the ", "a ", "an "] where s.hasPrefix(a) { s.removeFirst(a.count) }
        return s
    }
    /// Head word for grammar: last word before the first preposition.
    static func headWord(_ d: String) -> String {
        var c = " " + clean(d) + " "
        for p in preps { if let r = c.range(of: p) { c = String(c[..<r.lowerBound]) } }
        return c.split(separator: " ").last.map(String.init) ?? clean(d)
    }
    static func isPlural(_ x: String) -> Bool {
        guard let w = x.split(separator: " ").last.map(String.init) else { return false }
        if ["glass", "grass", "moss", "canvas", "bus", "series"].contains(w) { return false }
        return w.hasSuffix("s") && !w.hasSuffix("ss")
    }
    static func whyKeep(desc: String, role: String, part: String, warnings: [String]) -> (why: String, keep: String) {
        let x = clean(desc), p = clean(part)
        let pl = isPlural(headWord(desc))
        func v(_ one: String, _ many: String) -> String { pl ? many : one }
        let partOf = p.isEmpty || p == "none" || p == x || x.contains(p) ? "the \(x)" : "the \(p) of the \(x)"
        switch role {
        case "landmark":
            return ("The \(x) \(v("shows", "show")) where the photo was taken.",
                    "Keep \(partOf) beside the person, not hidden behind the head.")
        case "leadingLine":
            return ("The \(x) \(v("leads", "lead")) the eye through the photo.",
                    "Keep \(partOf) visible next to the person so its shape still reads.")
        case "frame":
            return ("The \(x) \(v("frames", "frame")) the scene around the person.",
                    "Keep \(partOf) along the edge of the photo.")
        case "plainBackdrop":
            return ("The \(x) \(v("is", "are")) calm and clean, so the person stands out.",
                    "Keep a clean stretch of the \(x) behind the head and shoulders"
                        + (warnings.isEmpty ? "." : ", away from the \(warnings.joined(separator: " and the ")).")) 
        case "pattern":
            return ("The repeating \(x) \(v("adds", "add")) texture without hiding the person.",
                    "Keep part of \(partOf) visible around the person.")
        default:
            return ("The \(x) \(v("adds", "add")) glow and mood to the photo.", "Keep \(partOf) uncovered.")
        }
    }
    static func roleTitle(_ r: String) -> String {
        switch r {
        case "landmark": "Landmark"
        case "leadingLine": "Leading line"
        case "frame": "Frame"
        case "plainBackdrop": "Plain backdrop"
        case "pattern": "Pattern"
        case "lightOrReflection": "Light / reflection"
        default: r
        }
    }
    static func roleIcon(_ r: String) -> String {
        switch r {
        case "landmark": "building.columns"
        case "leadingLine": "arrow.up.forward"
        case "frame": "rectangle.dashed"
        case "plainBackdrop": "square"
        case "pattern": "square.grid.3x3"
        case "lightOrReflection": "sun.max"
        default: "sparkles"
        }
    }
}

// MARK: - Role guard v2 (drops ideas whose head noun clearly doesn't fit the role)

nonisolated enum SceneRoleGuard {
    static let version = "guard-v2"
    static let blocked: [String: Set<String>] = [
        "landmark": ["menu", "menus", "flyer", "flyers", "advertisement", "advertisements", "ad", "ads",
                     "person", "people", "man", "woman", "men", "women", "crowd", "pedestrian", "pedestrians"],
        "frame": ["floor", "floors", "tile", "tiles", "ground", "pavement", "carpet", "rug", "floorboards"],
        "leadingLine": ["tree", "palm", "bush", "person", "car", "crowd"],
    ]
    /// Frame only for things that really surround the view (allow list).
    static let frameAllowed: Set<String> = ["door", "doors", "doorway", "doorways", "arch", "arches", "archway", "archways",
        "window", "windows", "gate", "gates", "opening", "openings", "canopy", "canopies", "awning", "awnings",
        "leaves", "branches", "foliage", "frame", "frames", "curtain", "curtains", "columns", "pillars"]
    /// Allowed as a frame only when said to be on both / several sides.
    static let frameSides: Set<String> = ["wall", "walls", "railing", "railings", "fence", "fences", "trees", "plants", "columns", "pillars"]
    /// A plain backdrop sits behind the person, not under their feet.
    static let groundWords: Set<String> = ["floor", "floors", "tile", "tiles", "ground", "grass", "lawn", "pavement", "paved",
        "path", "paths", "road", "street", "sidewalk", "walkway", "carpet", "rug", "floorboards", "deck", "asphalt", "gravel"]
    static let preps = [" with ", " of ", " on ", " in ", " near ", " at ", " along ", " above ", " below ", " under ", " behind ",
                        " across ", " over ", " through ", " from ", " around ", " beside ", " between ", " into ", " against ", " by "]

    static func corePhrase(_ desc: String) -> [String] {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz'- ")
        var c = " " + String(desc.lowercased().map { allowed.contains($0) ? $0 : " " }) + " "
        for p in preps { if let r = c.range(of: p) { c = String(c[..<r.lowerBound]) + " " } }
        var w = c.split(separator: " ").map(String.init).filter { !["a", "an", "the"].contains($0) }
        while w.count > 1, let last = w.last, last.hasSuffix("ing") { w.removeLast() }
        return w
    }
    static func head(_ desc: String) -> String { corePhrase(desc).last ?? "" }
    static func words(_ desc: String) -> [String] {
        desc.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }
    static func frameOK(_ desc: String) -> Bool {
        let h = head(desc)
        if frameAllowed.contains(h) { return true }
        let l = " " + words(desc).joined(separator: " ") + " "
        return frameSides.contains(h) && [" both sides ", " sides of ", " on the sides ", " each side "].contains { l.contains($0) }
    }
    static func groundy(_ desc: String) -> Bool {
        let core = corePhrase(desc)
        let pool = head(desc) == "surface" ? words(desc) : core
        return pool.contains { groundWords.contains($0) } && !core.contains { ["wall", "walls", "curtain", "backdrop"].contains($0) }
    }
    static func isBlocked(_ desc: String, role: String) -> Bool {
        if blocked[role]?.contains(head(desc)) ?? false { return true }
        switch role {
        case "frame": return !frameOK(desc)
        case "plainBackdrop": return groundy(desc)
        default: return false
        }
    }
}

// MARK: - Person guide v1.2 (meters, phone height, shot, thirds; side picked by the user)

nonisolated enum ScenePersonGuide {
    static let version = "guide-v1.2"
    static let overheadWords: Set<String> = ["ceiling", "ceilings", "roof", "rafters", "overhead", "canopy", "beams", "beam", "skylight"]
    static let safety = "Only follow this if the spot is safe and easy to reach. If not, pick another idea."
    static let note = "Distances are a starting point. Adjust them to the place."

    /// Full name when ≤ 6 words, else the core phrase.
    static func name(_ element: String) -> String {
        let full = SceneText.clean(element)
        if full.split(separator: " ").count <= 6 { return full }
        let core = SceneRoleGuard.corePhrase(element).joined(separator: " ")
        return core.isEmpty ? full : core
    }
    static func isOverhead(_ element: String) -> Bool {
        !Set(element.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)).isDisjoint(with: overheadWords)
    }
    static func lines(_ i: SceneIdea) -> (person: String, photographer: String) {
        let x = name(i.element)
        let el = "the \(x)"
        let pl = SceneText.isPlural(SceneRoleGuard.head(i.element))
        func v(_ one: String, _ many: String) -> String { pl ? many : one }
        let it = pl ? "they" : "it"
        switch i.role {
        case "leadingLine" where isOverhead(i.element):
            var o = x
            for w in [" above", " overhead"] where o.hasSuffix(w) { o = String(o.dropLast(w.count)) }
            return ("Stand under the \(o), 3 to 5 m from the camera. Face the camera.",
                    "Hold the phone at waist height, tilted a little up, portrait. Fit the \(o) in the top half of the screen and the whole person in the bottom half.")
        case "leadingLine":
            return ("Stand on or right next to \(el), 4 to 6 m from the camera.",
                    "Hold the phone at waist height, portrait. Start \(el) from a bottom corner of the screen so \(it) \(v("leads", "lead")) up to the person's feet.")
        case "landmark":
            return ("Stand 2 to 3 m in front of \(el), a little to one side so you do not cover \(pl ? "them" : "it"). Face the camera.",
                    "Stand 4 to 6 m from the person, phone at chest height, portrait. Put the person on the left or right third of the screen and \(el) on the other side. Show the whole body with a small gap above the head.")
        case "frame":
            return ("Stand 3 to 5 m past \(el), in the middle of the opening.",
                    "Stand 1 to 2 m behind \(el) so \(it) \(v("covers", "cover")) the edges of the screen. Keep the whole person in the middle.")
        case "plainBackdrop":
            return ("Stand 1 to 2 m in front of \(el), not against \(pl ? "them" : "it"), so no shadow falls behind you.",
                    "Stand 2 to 3 m away, phone at chest height. Frame from the waist up, with only \(el) behind the head.")
        case "pattern":
            return ("Stand about 1 m in front of \(el). Face the camera.",
                    "Stand 2 to 3 m away, phone at chest height. Fill the background with the \(x) and put the person on the left or right third.")
        default:
            return ("Stand 1 to 2 m to the side of \(el), so \(it) \(v("stays", "stay")) in view and not behind your head.",
                    "Stand 3 to 4 m away, phone at chest height. Keep \(el) on the other side of the screen from the person. Do not point the camera straight into a bright light.")
        }
    }
}

// MARK: - InputCheck v1 (soft block before asking the model; thresholds frozen in the prototype)

nonisolated enum SceneInputCheck {
    struct Features: Equatable, Sendable {
        var p50, p90, low, blob, blobSmooth, blobRB, coh, lum, dark: Double
    }
    static let grid = 8
    static let lowDetail: Float = 0.0015
    static let blurThreshold = 0.0067     // blurry when p90 < this
    static let darkThreshold = 0.90       // too dark when dark ≥ this
    enum Status: String, Sendable { case ok, blurry, tooDark }
    static func status(_ f: Features) -> Status {
        if f.dark >= darkThreshold { return .tooDark }
        if f.p90 < blurThreshold { return .blurry }
        return .ok
    }
    static func message(_ s: Status) -> String {
        switch s {
        case .blurry: "The view looks blurry. Hold the phone still and check the lens isn't covered."
        case .tooDark: "The view is too dark. Find more light."
        case .ok: ""
        }
    }
    static func jpeg(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    /// Downscales to a 512 px long side (EXIF orientation applied), then Laplacian-variance features on an 8×8 grid.
    static func features(_ data: Data) -> Features? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512] as CFDictionary) else { return nil }
        let w = cg.width, h = cg.height
        guard w > 16, h > 16 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var r = [Float](repeating: 0, count: w * h), gC = r, b = r, g = r
        for i in 0..<(w * h) {
            r[i] = Float(px[i * 4]) / 255; gC[i] = Float(px[i * 4 + 1]) / 255; b[i] = Float(px[i * 4 + 2]) / 255
            g[i] = (r[i] + gC[i] + b[i]) / 3
        }
        // Laplacian (interior) + gradien
        let lw = w - 2, lh = h - 2
        var lap = [Float](repeating: 0, count: lw * lh)
        var jxx: Double = 0, jyy: Double = 0, jxy: Double = 0
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let c = y * w + x
                lap[(y - 1) * lw + (x - 1)] = -4 * g[c] + g[c - w] + g[c + w] + g[c - 1] + g[c + 1]
                let gx = Double(g[c + 1] - g[c - 1]), gy = Double(g[c + w] - g[c - w])
                if gx * gx + gy * gy > 1e-4 { jxx += gx * gx; jyy += gy * gy; jxy += gx * gy }
            }
        }
        let coh = ((jxx - jyy) * (jxx - jyy) + 4 * jxy * jxy).squareRoot() / (jxx + jyy + 1e-9)
        // variansi Laplacian per kotak 8×8
        let G = grid, th = lh / G, tw = lw / G
        var T = [Float](repeating: 0, count: G * G)
        for i in 0..<G {
            for j in 0..<G {
                var s1: Double = 0, s2: Double = 0
                for y in (i * th)..<((i + 1) * th) { for x in (j * tw)..<((j + 1) * tw) { let v = Double(lap[y * lw + x]); s1 += v; s2 += v * v } }
                let n = Double(th * tw); T[i * G + j] = Float(s2 / n - (s1 / n) * (s1 / n))
            }
        }
        func pct(_ a: [Float], _ q: Double) -> Double {
            let s = a.sorted(); let k = q * Double(s.count - 1); let lo = Int(k.rounded(.down)), hi = min(lo + 1, s.count - 1)
            return Double(s[lo]) + (Double(s[hi]) - Double(s[lo])) * (k - Double(lo))
        }
        // blob detail-rendah terbesar yang menyentuh tepi (tetangga 4)
        let low = T.map { $0 < lowDetail }
        var seen = [Bool](repeating: false, count: G * G), best: [Int] = []
        for start in 0..<(G * G) where low[start] && !seen[start] {
            var stack = [start], comp: [Int] = []; seen[start] = true
            while let c = stack.popLast() {
                comp.append(c); let a = c / G, bb = c % G
                for (da, db) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let x = a + da, y = bb + db
                    if x >= 0, x < G, y >= 0, y < G, low[x * G + y], !seen[x * G + y] { seen[x * G + y] = true; stack.append(x * G + y) }
                }
            }
            if comp.contains(where: { $0 / G == 0 || $0 / G == G - 1 || $0 % G == 0 || $0 % G == G - 1 }), comp.count > best.count { best = comp }
        }
        var blobRB = 0.0, blobSmooth = 0.0
        if !best.isEmpty {
            let rh = h / G, rw = w / G
            var sr: Double = 0, sb: Double = 0, n: Double = 0
            for c in best {
                let a = c / G, bb = c % G
                for y in (a * rh)..<((a + 1) * rh) { for x in (bb * rw)..<((bb + 1) * rw) { sr += Double(r[y * w + x]); sb += Double(b[y * w + x]); n += 1 } }
            }
            blobRB = (sr - sb) / max(n, 1)
            blobSmooth = pct(best.map { T[$0] }, 0.5)
        }
        let lum = g.reduce(0) { $0 + Double($1) } / Double(g.count)
        let dark = Double(g.filter { $0 < 0.08 }.count) / Double(g.count)
        return Features(p50: pct(T, 0.5), p90: pct(T, 0.9), low: Double(low.filter { $0 }.count) / Double(G * G),
                        blob: Double(best.count) / Double(G * G), blobSmooth: blobSmooth, blobRB: blobRB, coh: coh, lum: lum, dark: dark)
    }

}
