//
//  HumanSubjectValidator.swift
//  gophoto
//
//  Checks, before the preference analysis runs, that each reference photo shows exactly ONE
//  person in its foreground: the user. A preference is analysed only from the photos that do
//  (`validatedPhotos`), and only when at least `minimumValidPhotos` of them do. Landscapes,
//  buildings, animals or objects alone teach the guide nothing about how the user frames people,
//  and a group photo does not say which person the framing is about. People clearly behind the
//  subject (passers-by) do not count. The preference itself keeps every photo the user chose
//  (`sourcePhotos`); nothing is removed from it here.
//
//  Per photo (static photos only; the camera's `PersonDetector` tracks video frames and is not
//  used, and nothing here runs during the live preview):
//  A. `PhotoPreparer` (the analysis pipeline's own) renders one upright, size-limited image.
//     Vision's `VNDetectHumanRectanglesRequest` (all observations) and face rectangles find the
//     people; overlapping boxes of one person are merged.
//  B. Only when there are two or more people: Depth Anything V2 (`DepthEvidenceModel`, the
//     analysis pipeline's verified wrapper: LARGER = NEARER, relative, not metres) estimates
//     depth on the same upright image, LETTERBOXED to the model's declared input size (aspect
//     ratio kept, centred, black padding; the model then sees it unscaled). The output cells
//     over the padding are dropped and the rest re-normalised (min-max over the photo only), so
//     the result is a depth grid of the photo itself: a normalised position in it is the same
//     position in the photo (error under one depth cell). Vision boxes are flipped to top-left
//     once (`ImageSpace`), the convention of the depth grid.
//  C. Each person's depth: the median over a central torso region of their box (minus parts
//     covered by other people's boxes), with its spread (interquartile range).
//  D. The nearest reliable person is the foreground reference; others at a similar depth join
//     the foreground group, clearly farther ones are background, and the rest are ambiguous.
//     Thresholds (`GroupingThresholds`, one place) are relative to the photo's own depth range
//     and to the measured spreads.
//
//  Outcomes: one foreground person (valid), none, several in the foreground (confirmed invalid),
//  ambiguous grouping (uncertain: neither valid nor removed), or a processing failure (image,
//  Vision or depth could not run: retried, never removed, never analysed).
//
//  Diagnostics (numbers only, no image data) go to the unified log, category
//  "subjectValidation", at debug level.
//
//  No UI state or navigation here: callers decide what to show.
//

import CoreGraphics
import Foundation
import Vision
import os

/// The outcome of checking one photo.
nonisolated enum HumanSubjectStatus: Equatable, Sendable {
    /// Exactly one person in the foreground (people clearly behind them do not count).
    case validSingleForegroundSubject
    /// The photo was read and checked, and no person was detected.
    case noPersonDetected
    /// The photo was read and checked: `count` (2 or more) people stand in the foreground.
    case multipleForegroundSubjects(count: Int)
    /// Several people, and depth could not tell reliably who is in the foreground.
    case uncertainForegroundGrouping
    /// The photo's pixels could not be loaded or prepared.
    case imageLoadFailed(String)
    /// Vision could not process the photo.
    case visionFailed(String)
    /// Several people were found and the depth model could not run on the photo.
    case depthFailed(String)

    var isValid: Bool { self == .validSingleForegroundSubject }

    /// Checked successfully and rejected (no person, or several in the foreground).
    var isConfirmedInvalid: Bool {
        switch self {
        case .noPersonDetected, .multipleForegroundSubjects: return true
        default: return false
        }
    }

    /// Checked, but the result is not reliable enough to keep or remove the photo.
    var isUncertain: Bool { self == .uncertainForegroundGrouping }

    var isProcessingFailure: Bool {
        switch self {
        case .imageLoadFailed, .visionFailed, .depthFailed: return true
        default: return false
        }
    }
}

/// Which of a preference's photos show exactly one person, in the preference's photo order.
struct HumanSubjectValidationResult {
    /// Every photo inspected: the preference's photos, unchanged.
    let sourcePhotos: [PhotoItem]
    /// Photos with exactly one person: the only ones the analysis may use.
    let validatedPhotos: [PhotoItem]
    /// Photos checked successfully and rejected: `noPersonPhotos` + `multiplePeoplePhotos`, in
    /// photo order. Continue removes these from the preference.
    let invalidPhotos: [PhotoItem]
    /// Checked, no person detected.
    let noPersonPhotos: [PhotoItem]
    /// Checked, two or more people in the foreground.
    let multiplePeoplePhotos: [PhotoItem]
    /// Several people, foreground not reliably established: kept, not analysed, not removed.
    let uncertainPhotos: [PhotoItem]
    /// Photos that could not be loaded or checked (neither valid nor confirmed invalid).
    let failedPhotos: [PhotoItem]
    /// The outcome per photo (`PhotoItem.id`).
    let statuses: [UUID: HumanSubjectStatus]
    /// Confirmed invalid photos already removed from the preference by this check's run (no
    /// person / several in the foreground). Zero until `afterRemovingInvalidPhotos`.
    private(set) var removedNoPersonCount = 0
    private(set) var removedMultipleCount = 0
    var removedCount: Int { removedNoPersonCount + removedMultipleCount }

    /// The same check after its confirmed invalid photos left the preference: `remaining` (the
    /// saved photos) are the source now, and the removed counts are kept for the messages.
    func afterRemovingInvalidPhotos(remaining: [PhotoItem]) -> HumanSubjectValidationResult {
        var cleaned = HumanSubjectValidationResult(sourcePhotos: remaining, statuses: statuses)
        cleaned.removedNoPersonCount = removedNoPersonCount + noPersonPhotos.count
        cleaned.removedMultipleCount = removedMultipleCount + multiplePeoplePhotos.count
        return cleaned
    }

    var totalInspected: Int { sourcePhotos.count }
    var validCount: Int { validatedPhotos.count }
    var invalidCount: Int { invalidPhotos.count }
    var processingFailureCount: Int { failedPhotos.count }
    var hasProcessingFailures: Bool { !failedPhotos.isEmpty }
    var hasMultiplePeoplePhotos: Bool { !multiplePeoplePhotos.isEmpty }
    var uncertainCount: Int { uncertainPhotos.count }
    var hasUncertainPhotos: Bool { !uncertainPhotos.isEmpty }

    /// Enough single-person photos for the analysis to run (on `validatedPhotos` only).
    var hasEnoughValidPhotos: Bool { validCount >= HumanSubjectValidator.minimumValidPhotos }

    func status(of photoID: UUID) -> HumanSubjectStatus? { statuses[photoID] }

    init(sourcePhotos: [PhotoItem], statuses: [UUID: HumanSubjectStatus]) {
        var valid: [PhotoItem] = []
        var invalid: [PhotoItem] = []
        var noPerson: [PhotoItem] = []
        var multiple: [PhotoItem] = []
        var uncertain: [PhotoItem] = []
        var failed: [PhotoItem] = []
        for photo in sourcePhotos {
            switch statuses[photo.id] {
            case .validSingleForegroundSubject?:
                valid.append(photo)
            case .noPersonDetected?:
                invalid.append(photo)
                noPerson.append(photo)
            case .multipleForegroundSubjects?:
                invalid.append(photo)
                multiple.append(photo)
            case .uncertainForegroundGrouping?:
                uncertain.append(photo)
            // Not checked at all counts as a processing failure, never as an invalid photo.
            case .imageLoadFailed?, .visionFailed?, .depthFailed?, nil:
                failed.append(photo)
            }
        }
        self.sourcePhotos = sourcePhotos
        self.validatedPhotos = valid
        self.invalidPhotos = invalid
        self.noPersonPhotos = noPerson
        self.multiplePeoplePhotos = multiple
        self.uncertainPhotos = uncertain
        self.failedPhotos = failed
        self.statuses = statuses
    }

    // MARK: Messages
    //
    // Both are shown after the confirmed invalid photos were already removed (and saved):
    // counts are of the photos left, plus how many were removed.

    private static func photos(_ n: Int) -> String { "\(n) \(n == 1 ? "photo" : "photos")" }

    /// Photos kept but not used: they can be tapped on Photo Session Setup to check again or
    /// replace (uncertain / failed checks).
    private var keptButUnusedNote: String? {
        var notes: [String] = []
        if hasUncertainPhotos {
            notes.append("In \(Self.photos(uncertainCount)) we couldn't tell who the main person is.")
        }
        if hasProcessingFailures {
            notes.append("\(Self.photos(processingFailureCount)) couldn't be checked.")
        }
        guard !notes.isEmpty else { return nil }
        let count = uncertainCount + processingFailureCount
        return (notes + ["\(count == 1 ? "It stays" : "They stay") in your preference but won't be used; tap \(count == 1 ? "it" : "them") to check again or replace."]).joined(separator: " ")
    }

    static let exclusionTitle = "Some Photos Were Excluded"

    /// Enough valid photos left; invalid ones removed.
    var exclusionMessage: String {
        let removed = removedCount
        var parts = ["We found \(Self.photos(removed)) that didn't meet the requirements. Each photo must contain exactly one foreground subject. \(removed == 1 ? "This photo has" : "These photos have") been removed from your preference."]
        if let note = keptButUnusedNote { parts.append(note) }
        parts.append("Analysis will continue using your \(validCount) valid \(validCount == 1 ? "photo" : "photos").")
        return parts.joined(separator: " ")
    }

    static let warningTitle = "Not Enough Photos with People"

    /// Fewer than the minimum valid photos left.
    var warningMessage: String {
        var parts = ["You have \(validCount) valid \(validCount == 1 ? "photo" : "photos") with exactly one person in the foreground."]
        if removedCount > 0 {
            var reasons: [String] = []
            if removedNoPersonCount > 0 { reasons.append("\(Self.photos(removedNoPersonCount)) with no person") }
            if removedMultipleCount > 0 { reasons.append("\(Self.photos(removedMultipleCount)) with more than one person") }
            parts.append("We removed \(reasons.joined(separator: " and ")) from your preference.")
        }
        if let note = keptButUnusedNote { parts.append(note) }
        parts.append("Please add more photos featuring only yourself. At least \(HumanSubjectValidator.minimumValidPhotos) valid photos are required to analyze your photography style.")
        return parts.joined(separator: " ")
    }
}

nonisolated enum HumanSubjectValidator {
    /// Valid photos needed before a preference is analysed.
    static let minimumValidPhotos = 3
    /// Long edge the check runs at: enough for a person filling a small part of the frame.
    static let longEdge = 1024
    /// A clear subject: at least this confident and this large.
    static let minimumConfidence: Float = 0.5
    static let minimumBodySide: CGFloat = 0.04
    static let minimumFaceSide: CGFloat = 0.02

    static let log = Logger(subsystem: "co.mango.gophoto", category: "subjectValidation")

    /// Checks every photo (duplicates once) off the main actor and sorts them into valid,
    /// invalid, uncertain and failed photos, keeping the order of `photos`.
    @MainActor
    static func validate(_ photos: [PhotoItem]) async -> HumanSubjectValidationResult {
        var seen = Set<UUID>()
        let unique = photos.filter { seen.insert($0.id).inserted }
        let sources = unique.enumerated().map { index, photo in
            PhotoSource(id: photo.id, selectionOrder: index, image: photo.image,
                        focalLength35mm: photo.focalLength35mm)
        }
        let statuses = await detect(sources)
        return HumanSubjectValidationResult(sourcePhotos: unique, statuses: statuses)
    }

    /// Runs the check on a background task, one photo after another. The depth model is loaded
    /// at most once per call (only if a photo has several people) and released afterwards.
    static func detect(_ photos: [PhotoSource]) async -> [UUID: HumanSubjectStatus] {
        await Task.detached(priority: .userInitiated) {
            let depthModel = DepthEvidenceModel()
            var statuses: [UUID: HumanSubjectStatus] = [:]
            for photo in photos {
                statuses[photo.id] = await status(of: photo, depthModel: depthModel)
            }
            return statuses
        }.value
    }

    /// Check of one photo. Call off the main thread.
    static func status(of photo: PhotoSource, depthModel: DepthEvidenceModel) async -> HumanSubjectStatus {
        let tag = String(photo.id.uuidString.prefix(8))
        // Drops the upright image as soon as this photo is done.
        let image: CGImage
        switch PhotoPreparer.prepare(photo, longEdge: longEdge).outcome {
        case .ready(let upright, _): image = upright
        case .unreadable(let reason):
            log.debug("[\(tag, privacy: .public)] image load failed")
            return .imageLoadFailed(reason)
        }

        let bodyRequest = VNDetectHumanRectanglesRequest()
        bodyRequest.upperBodyOnly = false
        let faceRequest = VNDetectFaceRectanglesRequest()
        do {
            // `PhotoPreparer` already applied the photo's orientation.
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                .perform([bodyRequest, faceRequest])
        } catch {
            log.debug("[\(tag, privacy: .public)] Vision failed")
            return .visionFailed(error.localizedDescription)
        }

        let bodies = bodyRequest.results ?? []
        let people = candidates(bodies: bodies, faces: faceRequest.results ?? [])
        log.debug("[\(tag, privacy: .public)] Vision: \(bodies.count) body observations → \(people.count) people")
        for (i, person) in people.enumerated() {
            log.debug("[\(tag, privacy: .public)]   #\(i) \(person.isFaceOnly ? "face" : "body", privacy: .public) box \(describe(person.box), privacy: .public) conf \(person.confidence, format: .fixed(precision: 2)) clear \(person.isClear)")
        }

        // No clear person: none (a faint detection alone is not a subject).
        guard people.contains(where: \.isClear) else {
            log.debug("[\(tag, privacy: .public)] result: no person")
            return .noPersonDetected
        }
        if people.count == 1 {
            log.debug("[\(tag, privacy: .public)] result: one person (no depth needed)")
            return .validSingleForegroundSubject
        }

        // Several people: who is in the foreground?
        let depth: DepthGrid
        do {
            depth = try await letterboxedDepth(of: image, model: depthModel)
        } catch {
            log.debug("[\(tag, privacy: .public)] depth failed: \(error.localizedDescription, privacy: .public)")
            return .depthFailed(error.localizedDescription)
        }
        let result = groupForeground(people, depth: depth, tag: tag)
        log.debug("[\(tag, privacy: .public)] result: \(String(describing: result), privacy: .public)")
        return result
    }

    // MARK: A. People

    /// One detected person, image space (normalised, top-left origin, upright image).
    struct PersonCandidate: Sendable {
        var box: CGRect
        var confidence: Float
        var isClear: Bool
        /// Found by its face only (no body box): the face box is the sampling region.
        var isFaceOnly: Bool
    }

    /// Body boxes this confident (and this large) count as people. Lower than the bar for a clear
    /// subject, so a second person in the photo is not missed.
    static let countingConfidence: Float = 0.4
    static let countingBodySide: CGFloat = 0.03
    static let countingFaceSide: CGFloat = 0.015
    /// Two boxes of one person: they overlap this much (intersection over union), or the smaller
    /// lies this much inside the larger (an upper-body box inside a full-body box).
    static let samePersonIoU: CGFloat = 0.5
    static let samePersonContainment: CGFloat = 0.8

    /// Every person in the photo (all observations read, duplicates merged), strongest first.
    static func candidates(bodies: [VNHumanObservation], faces: [VNFaceObservation]) -> [PersonCandidate] {
        func sized(_ box: CGRect, _ side: CGFloat) -> Bool { box.width >= side && box.height >= side }
        func imageBox(_ r: CGRect) -> CGRect {
            ImageSpace.clamped(ImageSpace.rect(fromVisionX: Double(r.origin.x), y: Double(r.origin.y),
                                               width: Double(r.width), height: Double(r.height)))
        }
        func merge(_ candidate: PersonCandidate, into list: inout [PersonCandidate]) {
            if let i = list.firstIndex(where: { samePerson($0.box, candidate.box) }) {
                list[i].isClear = list[i].isClear || candidate.isClear
                list[i].confidence = max(list[i].confidence, candidate.confidence)
            } else {
                list.append(candidate)
            }
        }

        var people: [PersonCandidate] = []
        for body in bodies.sorted(by: { $0.confidence > $1.confidence })
        where body.confidence >= countingConfidence && sized(body.boundingBox, countingBodySide) {
            let clear = body.confidence >= minimumConfidence && sized(body.boundingBox, minimumBodySide)
            merge(PersonCandidate(box: imageBox(body.boundingBox), confidence: body.confidence,
                                  isClear: clear, isFaceOnly: false), into: &people)
        }

        // A face inside a counted body is that person; any other face is another person
        // (close-ups with no body box, or people whose bodies Vision merged into one box).
        let bodyBoxes = people.map(\.box)
        var extraFaces: [PersonCandidate] = []
        for face in faces.sorted(by: { $0.confidence > $1.confidence })
        where face.confidence >= countingConfidence && sized(face.boundingBox, countingFaceSide) {
            let box = imageBox(face.boundingBox)
            let centre = CGPoint(x: box.midX, y: box.midY)
            if bodyBoxes.contains(where: { $0.insetBy(dx: -$0.width * 0.05, dy: -$0.height * 0.05).contains(centre) }) {
                continue
            }
            let clear = face.confidence >= minimumConfidence && sized(face.boundingBox, minimumFaceSide)
            merge(PersonCandidate(box: box, confidence: face.confidence, isClear: clear, isFaceOnly: true),
                  into: &extraFaces)
        }
        return people + extraFaces
    }

    /// Whether two boxes (normalised) are the same person.
    static func samePerson(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return false }
        let intersection = overlap.width * overlap.height
        let areaA = a.width * a.height, areaB = b.width * b.height
        let union = areaA + areaB - intersection
        if union > 0, intersection / union >= samePersonIoU { return true }
        let smaller = min(areaA, areaB)
        return smaller > 0 && intersection / smaller >= samePersonContainment
    }

    // MARK: B. Depth (aspect ratio kept)

    /// Runs the depth model on `image` letterboxed to the model's input size and returns the
    /// depth of the photo area only, re-normalised over it (1 = nearest point of the photo,
    /// 0 = farthest), in the photo's own normalised coordinates.
    static func letterboxedDepth(of image: CGImage, model: DepthEvidenceModel) async throws -> DepthGrid {
        let input = try await model.inputSize()
        let W = Double(input.width), H = Double(input.height)
        let w = Double(image.width), h = Double(image.height)
        guard w > 0, h > 0 else { throw SceneModelError.unexpectedOutput("Depth: empty image") }

        // Aspect fit, centred, whole pixels.
        let scale = min(W / w, H / h)
        let contentW = max(1, (w * scale).rounded()), contentH = max(1, (h * scale).rounded())
        let offsetX = ((W - contentW) / 2).rounded(.down), offsetY = ((H - contentH) / 2).rounded(.down)

        guard let context = CGContext(data: nil, width: input.width, height: input.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw SceneModelError.unexpectedOutput("Depth: could not letterbox the photo")
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))
        context.interpolationQuality = .high
        // Core Graphics' origin is bottom-left: the top padding is `offsetY` from the top.
        context.draw(image, in: CGRect(x: offsetX, y: H - offsetY - contentH, width: contentW, height: contentH))
        guard let letterboxed = context.makeImage() else {
            throw SceneModelError.unexpectedOutput("Depth: could not letterbox the photo")
        }

        let full = try await model.estimate(letterboxed)

        // Output cells fully inside the photo area (grid rows top-down, like the image).
        let sx = Double(full.width) / W, sy = Double(full.height) / H
        let x0 = Int((offsetX * sx).rounded(.up)), x1 = Int(((offsetX + contentW) * sx).rounded(.down))
        let y0 = Int((offsetY * sy).rounded(.up)), y1 = Int(((offsetY + contentH) * sy).rounded(.down))
        guard x1 - x0 >= 2, y1 - y0 >= 2 else { throw SceneModelError.unexpectedOutput("Depth: photo area too small") }

        var values = [Float]()
        values.reserveCapacity((x1 - x0) * (y1 - y0))
        for y in y0..<y1 {
            let row = y * full.width
            for x in x0..<x1 { values.append(full.nearness[row + x]) }
        }
        guard let lo = values.min(), let hi = values.max(), hi - lo > 1e-4 else {
            throw SceneModelError.unexpectedOutput("Depth: no variation inside the photo")
        }
        let range = hi - lo
        return DepthGrid(width: x1 - x0, height: y1 - y0, nearness: values.map { ($0 - lo) / range })
    }

    // MARK: C. Depth per person

    /// A person's depth: median nearness of their torso region, its spread and sample count.
    struct PersonDepth: Sendable {
        var median: Float
        var spread: Float
        var samples: Int
        var isReliable: Bool
    }

    /// Torso region of a body box (central 40 % of the width, 22–60 % of the height: chest and
    /// belly for a full body, chest for an upper body), or the central face for a face-only box.
    static func samplingRegion(of person: PersonCandidate) -> CGRect {
        let b = person.box
        if person.isFaceOnly {
            return ImageSpace.core(of: b, fraction: 0.6)
        }
        return CGRect(x: b.minX + b.width * 0.30, y: b.minY + b.height * 0.22,
                      width: b.width * 0.40, height: b.height * 0.38)
    }

    /// The person's depth from the cells of their sampling region that no other person's box
    /// covers (an occluded person must not borrow the depth of whoever stands in front of them).
    /// Too few such cells, or too wide a spread: not reliable.
    static func depth(of person: PersonCandidate, others: [PersonCandidate], in grid: DepthGrid,
                      range: Float, thresholds: GroupingThresholds) -> PersonDepth {
        let region = ImageSpace.clamped(samplingRegion(of: person))
        let x0 = max(0, Int((region.minX * CGFloat(grid.width)).rounded(.down)))
        let x1 = min(grid.width - 1, Int((region.maxX * CGFloat(grid.width)).rounded(.up)))
        let y0 = max(0, Int((region.minY * CGFloat(grid.height)).rounded(.down)))
        let y1 = min(grid.height - 1, Int((region.maxY * CGFloat(grid.height)).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return PersonDepth(median: 0, spread: 1, samples: 0, isReliable: false) }

        var values: [Float] = []
        for y in y0...y1 {
            for x in x0...x1 {
                let p = CGPoint(x: (CGFloat(x) + 0.5) / CGFloat(grid.width), y: (CGFloat(y) + 0.5) / CGFloat(grid.height))
                if others.contains(where: { $0.box.contains(p) }) { continue }
                values.append(grid.nearness[y * grid.width + x])
            }
        }
        guard values.count >= thresholds.minDepthSamples else {
            return PersonDepth(median: values.isEmpty ? 0 : quantile(values, 0.5), spread: 1,
                               samples: values.count, isReliable: false)
        }
        let sorted = values.sorted()
        let spread = quantileSorted(sorted, 0.75) - quantileSorted(sorted, 0.25)
        return PersonDepth(median: quantileSorted(sorted, 0.5), spread: spread, samples: values.count,
                           isReliable: range > 0 && spread <= thresholds.maxSpreadShare * range)
    }

    // MARK: D. Foreground group

    /// Every grouping threshold, in one place. Depth values are relative (Depth Anything is
    /// monocular and min-max normalised per photo), so gaps are measured as shares of the photo's
    /// own depth range (10th–90th percentile of nearness: robust to a few extreme cells such as
    /// sky or a hand at the lens) and against the people's own measured spread. Defaults are
    /// first estimates, NOT validated on device: tune them with the debug log (category
    /// "subjectValidation") on real photos.
    struct GroupingThresholds: Sendable {
        /// Fewer torso cells than this and a person's median is not trusted (8 cells ≈ a torso
        /// 2×4 cells wide in a ~290×390 depth grid: a very small or mostly hidden person).
        var minDepthSamples = 8
        /// A torso spread (interquartile range) wider than this share of the photo's depth range
        /// means the region mixes the person with background: not trusted.
        var maxSpreadShare: Float = 0.6
        /// Below this depth range the map is too flat to separate anyone (a uniform scene, or
        /// the model failing on it): every multi-person photo is uncertain.
        var minDepthRange: Float = 0.12
        /// "Same depth" floor: people side by side differ by about their own torso spread; the
        /// floor keeps two very uniform torsos from being split by a tiny model difference.
        var sameShare: Float = 0.12
        /// "Clearly behind" floor: a passer-by a few metres back sits well down the depth range.
        var backgroundShare: Float = 0.30

        static let standard = GroupingThresholds()
    }

    static func groupForeground(_ people: [PersonCandidate], depth grid: DepthGrid, tag: String,
                                thresholds: GroupingThresholds = .standard) -> HumanSubjectStatus {
        // The photo's own depth range (robust): every gap is a share of it.
        let step = max(1, grid.nearness.count / 20_000)
        let sample = stride(from: 0, to: grid.nearness.count, by: step).map { grid.nearness[$0] }.sorted()
        let range = quantileSorted(sample, 0.9) - quantileSorted(sample, 0.1)

        let depths = people.indices.map { i in
            depth(of: people[i], others: people.indices.filter { $0 != i }.map { people[$0] },
                  in: grid, range: range, thresholds: thresholds)
        }
        log.debug("[\(tag, privacy: .public)] depth grid \(grid.width)x\(grid.height) (photo area), range p10–p90 \(range, format: .fixed(precision: 3))")
        for (i, d) in depths.enumerated() {
            log.debug("[\(tag, privacy: .public)]   #\(i) median \(d.median, format: .fixed(precision: 3)) spread \(d.spread, format: .fixed(precision: 3)) n \(d.samples) reliable \(d.isReliable)")
        }
        guard range >= thresholds.minDepthRange else {
            log.debug("[\(tag, privacy: .public)] depth map too flat to separate people")
            return .uncertainForegroundGrouping
        }

        // Reference: the nearest reliable person (larger nearness = nearer, verified polarity).
        guard let ref = depths.indices.filter({ depths[$0].isReliable })
                .max(by: { depths[$0].median < depths[$1].median }) else {
            log.debug("[\(tag, privacy: .public)] no reliable depth for any person")
            return .uncertainForegroundGrouping
        }

        var foreground = [ref], ambiguous: [Int] = []
        for i in depths.indices where i != ref {
            let d = depths[i]
            let gap = (depths[ref].median - d.median) / range
            // Same group: within the larger of the floor and the two torsos' own spread (as a
            // share of the range). Background: at least twice that, so the undecided band is never
            // narrower than the same-depth band (no knife edge between "together" and "behind").
            let pooledSpread = max(depths[ref].spread, d.spread) / range
            let same = max(thresholds.sameShare, pooledSpread)
            let background = max(thresholds.backgroundShare, 2 * same)
            let decision: String
            if !d.isReliable {
                ambiguous.append(i); decision = "ambiguous (depth not measurable)"
            } else if gap <= same {
                foreground.append(i); decision = "foreground"
            } else if gap >= background {
                decision = "background"
            } else {
                ambiguous.append(i); decision = "ambiguous"
            }
            log.debug("[\(tag, privacy: .public)]   #\(i) vs #\(ref): gap \(gap, format: .fixed(precision: 3)) (same ≤ \(same, format: .fixed(precision: 3)), background ≥ \(background, format: .fixed(precision: 3))) → \(decision, privacy: .public)")
        }

        if foreground.count >= 2 { return .multipleForegroundSubjects(count: foreground.count) }
        if !ambiguous.isEmpty { return .uncertainForegroundGrouping }
        // The only foreground person must be a clear subject, not a faint detection in front
        // of the real one.
        return people[ref].isClear ? .validSingleForegroundSubject : .uncertainForegroundGrouping
    }

    // MARK: Helpers

    static func quantile(_ values: [Float], _ q: Float) -> Float { quantileSorted(values.sorted(), q) }

    static func quantileSorted(_ sorted: [Float], _ q: Float) -> Float {
        guard !sorted.isEmpty else { return 0 }
        let position = q * Float(sorted.count - 1)
        let lower = Int(position.rounded(.down)), upper = min(sorted.count - 1, lower + 1)
        let t = position - Float(lower)
        return sorted[lower] * (1 - t) + sorted[upper] * t
    }

    static func describe(_ r: CGRect) -> String {
        String(format: "(%.2f, %.2f, %.2f×%.2f)", r.minX, r.minY, r.width, r.height)
    }
}
