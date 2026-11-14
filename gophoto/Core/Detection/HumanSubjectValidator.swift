//
//  HumanSubjectValidator.swift
//  gophoto
//
//  Checks, before the preference analysis runs, that each reference photo shows exactly ONE
//  person: the user. A preference is analysed only from the photos that do (`validatedPhotos`),
//  and only when at least `minimumValidPhotos` of them do. Landscapes, buildings, animals or
//  objects alone teach the guide nothing about how the user frames people, and a group photo
//  does not say which person the framing is about. The preference itself keeps every photo the
//  user chose (`sourcePhotos`); nothing is removed from it here.
//
//  Static photos only. The camera's `PersonDetector` keeps a subject lock and a tracker across
//  video frames, so it is not used here. Each photo is made upright and size-limited by the
//  analysis pipeline's own `PhotoPreparer`, then Vision's `VNDetectHumanRectanglesRequest`
//  (full or upper body) finds the people, with face detection for close-ups and for people
//  whose bodies merge into one box. All observations are read and counted; overlapping boxes
//  of the same person count once.
//
//  A photo that could not be loaded or checked is a processing failure, never a confirmed
//  invalid photo, and never analysed.
//
//  No UI state or navigation here: callers decide what to show.
//

import Foundation
import Vision

/// The outcome of checking one photo.
nonisolated enum HumanSubjectStatus: Equatable, Sendable {
    /// Exactly one person was detected.
    case validSinglePerson
    /// The photo was read and checked, and no person was detected.
    case noPersonDetected
    /// The photo was read and checked, and `count` (2 or more) people were detected.
    case multiplePeopleDetected(count: Int)
    /// The photo's pixels could not be loaded or prepared.
    case imageLoadFailed(String)
    /// Vision could not process the photo.
    case visionFailed(String)

    var isValid: Bool { self == .validSinglePerson }

    /// Checked successfully and rejected (no person, or more than one).
    var isConfirmedInvalid: Bool {
        switch self {
        case .noPersonDetected, .multiplePeopleDetected: return true
        case .validSinglePerson, .imageLoadFailed, .visionFailed: return false
        }
    }

    var isProcessingFailure: Bool {
        switch self {
        case .validSinglePerson, .noPersonDetected, .multiplePeopleDetected: return false
        case .imageLoadFailed, .visionFailed: return true
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
    /// Checked, two or more people detected.
    let multiplePeoplePhotos: [PhotoItem]
    /// Photos that could not be loaded or checked (neither valid nor confirmed invalid).
    let failedPhotos: [PhotoItem]
    /// The outcome per photo (`PhotoItem.id`).
    let statuses: [UUID: HumanSubjectStatus]

    var totalInspected: Int { sourcePhotos.count }
    var validCount: Int { validatedPhotos.count }
    var invalidCount: Int { invalidPhotos.count }
    var processingFailureCount: Int { failedPhotos.count }
    var hasProcessingFailures: Bool { !failedPhotos.isEmpty }
    var hasMultiplePeoplePhotos: Bool { !multiplePeoplePhotos.isEmpty }

    /// Enough single-person photos for the analysis to run (on `validatedPhotos` only).
    var hasEnoughValidPhotos: Bool { validCount >= HumanSubjectValidator.minimumValidPhotos }

    func status(of photoID: UUID) -> HumanSubjectStatus? { statuses[photoID] }

    init(sourcePhotos: [PhotoItem], statuses: [UUID: HumanSubjectStatus]) {
        var valid: [PhotoItem] = []
        var invalid: [PhotoItem] = []
        var noPerson: [PhotoItem] = []
        var multiple: [PhotoItem] = []
        var failed: [PhotoItem] = []
        for photo in sourcePhotos {
            switch statuses[photo.id] {
            case .validSinglePerson?:
                valid.append(photo)
            case .noPersonDetected?:
                invalid.append(photo)
                noPerson.append(photo)
            case .multiplePeopleDetected?:
                invalid.append(photo)
                multiple.append(photo)
            // Not checked at all counts as a processing failure, never as an invalid photo.
            case .imageLoadFailed?, .visionFailed?, nil:
                failed.append(photo)
            }
        }
        self.sourcePhotos = sourcePhotos
        self.validatedPhotos = valid
        self.invalidPhotos = invalid
        self.noPersonPhotos = noPerson
        self.multiplePeoplePhotos = multiple
        self.failedPhotos = failed
        self.statuses = statuses
    }

    // MARK: Exclusion notice copy (enough valid photos, some invalid)

    static let exclusionTitle = "Some Photos Were Excluded"

    var exclusionMessage: String {
        func photos(_ n: Int) -> String { "\(n) \(n == 1 ? "photo" : "photos")" }
        let invalid = invalidCount
        return "Some of your uploaded photos didn't meet the photo requirements. Each photo must contain exactly one person. "
            + "We found \(invalid) invalid \(invalid == 1 ? "photo" : "photos"), so \(invalid == 1 ? "it" : "they") will be removed from this preference. "
            + "Analysis will continue using your \(validCount) valid \(validCount == 1 ? "photo" : "photos")."
            + (hasProcessingFailures ? " \(photos(processingFailureCount)) couldn't be checked; \(processingFailureCount == 1 ? "it stays" : "they stay") in the preference but won't be used." : "")
    }

    // MARK: Warning copy

    var warningTitle: String {
        hasProcessingFailures ? "Some Photos Couldn't Be Checked" : "Not Enough Photos of One Person"
    }

    var warningMessage: String {
        var parts = ["We found only \(validCount) \(validCount == 1 ? "photo" : "photos") showing exactly one person."]
        if hasMultiplePeoplePhotos {
            parts.append("Some photos contain more than one person. Please use photos featuring only yourself.")
        }
        if hasProcessingFailures {
            let failures = processingFailureCount
            parts.append("\(failures) \(failures == 1 ? "photo" : "photos") couldn't be checked. Try again, or add more photos where you're the only person.")
        } else {
            parts.append("Please add more photos where you're the only person.")
        }
        parts.append("At least \(HumanSubjectValidator.minimumValidPhotos) valid photos are required to analyze your photography style.")
        return parts.joined(separator: " ")
    }
}

nonisolated enum HumanSubjectValidator {
    /// Valid photos needed before a preference is analysed.
    static let minimumValidPhotos = 3
    /// Long edge the check runs at: enough for a person filling a small part of the frame.
    static let longEdge = 1024
    static let minimumConfidence: Float = 0.5
    /// Smallest body / face box (fraction of the frame's width and height) that counts.
    static let minimumBodySide: CGFloat = 0.04
    static let minimumFaceSide: CGFloat = 0.02

    /// Checks every photo (duplicates once) off the main actor and sorts them into valid,
    /// no-person and failed photos, keeping the order of `photos`.
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

    /// Runs the person check on a background thread, one photo after another.
    static func detect(_ photos: [PhotoSource]) async -> [UUID: HumanSubjectStatus] {
        await Task.detached(priority: .userInitiated) {
            var statuses: [UUID: HumanSubjectStatus] = [:]
            for photo in photos {
                statuses[photo.id] = status(of: photo)
            }
            return statuses
        }.value
    }

    /// Synchronous check of one photo. Call off the main thread.
    static func status(of photo: PhotoSource) -> HumanSubjectStatus {
        let prepared = PhotoPreparer.prepare(photo, longEdge: longEdge)
        let image: CGImage
        switch prepared.outcome {
        case .ready(let upright, _): image = upright
        case .unreadable(let reason): return .imageLoadFailed(reason)
        }

        let bodyRequest = VNDetectHumanRectanglesRequest()
        bodyRequest.upperBodyOnly = false
        let faceRequest = VNDetectFaceRectanglesRequest()
        do {
            // `PhotoPreparer` already applied the photo's orientation.
            try VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
                .perform([bodyRequest, faceRequest])
        } catch {
            return .visionFailed(error.localizedDescription)
        }

        return classify(bodies: bodyRequest.results ?? [], faces: faceRequest.results ?? [])
    }

    // MARK: Counting people

    /// Body boxes this confident (and this large) count as people. Lower than the bar for a clear
    /// subject, so a second person in the photo is not missed.
    static let countingConfidence: Float = 0.4
    static let countingBodySide: CGFloat = 0.03
    static let countingFaceSide: CGFloat = 0.015
    /// Two boxes of one person: they overlap this much (intersection over union), or the smaller
    /// lies this much inside the larger (an upper-body box inside a full-body box).
    static let samePersonIoU: CGFloat = 0.5
    static let samePersonContainment: CGFloat = 0.8

    /// Counts every person in the photo (all observations, duplicates merged) and classifies it.
    static func classify(bodies: [VNHumanObservation], faces: [VNFaceObservation]) -> HumanSubjectStatus {
        func sized(_ box: CGRect, _ side: CGFloat) -> Bool { box.width >= side && box.height >= side }

        // People from body boxes, strongest first, each merged with its duplicates.
        let bodyCandidates = bodies
            .filter { $0.confidence >= countingConfidence && sized($0.boundingBox, countingBodySide) }
            .sorted { $0.confidence > $1.confidence }
        var people: [(box: CGRect, isClear: Bool)] = []
        for body in bodyCandidates {
            let box = body.boundingBox
            let clear = body.confidence >= minimumConfidence && sized(box, minimumBodySide)
            if let index = people.firstIndex(where: { samePerson($0.box, box) }) {
                people[index].isClear = people[index].isClear || clear
            } else {
                people.append((box, clear))
            }
        }

        // Faces: a face inside a counted body is that person; any other face is another person
        // (close-ups with no body box, or people whose bodies Vision merged into one box).
        let faceCandidates = faces
            .filter { $0.confidence >= countingConfidence && sized($0.boundingBox, countingFaceSide) }
            .sorted { $0.confidence > $1.confidence }
        let bodyBoxes = people.map(\.box)
        var extraFaces: [(box: CGRect, isClear: Bool)] = []
        for face in faceCandidates {
            let box = face.boundingBox
            let centre = CGPoint(x: box.midX, y: box.midY)
            if bodyBoxes.contains(where: { $0.insetBy(dx: -$0.width * 0.05, dy: -$0.height * 0.05).contains(centre) }) {
                continue
            }
            let clear = face.confidence >= minimumConfidence && sized(box, minimumFaceSide)
            if let index = extraFaces.firstIndex(where: { samePerson($0.box, box) }) {
                extraFaces[index].isClear = extraFaces[index].isClear || clear
            } else {
                extraFaces.append((box, clear))
            }
        }
        people += extraFaces

        switch people.count {
        case 0:
            return .noPersonDetected
        case 1:
            // One faint detection only is not a clear subject.
            return people[0].isClear ? .validSinglePerson : .noPersonDetected
        default:
            return .multiplePeopleDetected(count: people.count)
        }
    }

    /// Whether two boxes (normalized) are the same person.
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
}
