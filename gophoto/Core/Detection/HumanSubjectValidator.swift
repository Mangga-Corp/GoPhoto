//
//  HumanSubjectValidator.swift
//  gophoto
//
//  Checks, before the preference analysis runs, that each reference photo shows a person.
//  A preference is analysed only from the photos that do (`validatedPhotos`), and only when at
//  least `minimumValidPhotos` of them do: landscapes, buildings, animals or objects alone teach
//  the guide nothing about how the user frames people. The preference itself keeps every photo
//  the user chose (`sourcePhotos`); nothing is removed from it here.
//
//  Static photos only. The camera's `PersonDetector` keeps a subject lock and a tracker across
//  video frames, so it is not used here. Each photo is made upright and size-limited by the
//  analysis pipeline's own `PhotoPreparer`, then Vision's `VNDetectHumanRectanglesRequest`
//  looks for a person (full or upper body), with face detection as a fallback for close-up
//  portraits that show no body.
//
//  A photo that could not be loaded or checked is a processing failure, never a confirmed
//  "no person" photo, and never analysed.
//
//  No UI state or navigation here: callers decide what to show.
//

import Foundation
import Vision

/// The outcome of checking one photo.
nonisolated enum HumanSubjectStatus: Equatable, Sendable {
    /// At least one person was detected.
    case valid
    /// The photo was read and checked, and no person was detected.
    case noHumanSubject
    /// The photo's pixels could not be loaded or prepared.
    case imageLoadFailed(String)
    /// Vision could not process the photo.
    case visionFailed(String)

    var isProcessingFailure: Bool {
        switch self {
        case .valid, .noHumanSubject: return false
        case .imageLoadFailed, .visionFailed: return true
        }
    }
}

/// Which of a preference's photos show a person, in the preference's photo order.
struct HumanSubjectValidationResult {
    /// Every photo inspected: the preference's photos, unchanged.
    let sourcePhotos: [PhotoItem]
    /// Photos with a detected person: the only ones the analysis may use.
    let validatedPhotos: [PhotoItem]
    /// Photos checked successfully with no person detected.
    let invalidPhotos: [PhotoItem]
    /// Photos that could not be loaded or checked (neither valid nor confirmed invalid).
    let failedPhotos: [PhotoItem]
    /// The outcome per photo (`PhotoItem.id`).
    let statuses: [UUID: HumanSubjectStatus]

    var totalInspected: Int { sourcePhotos.count }
    var validCount: Int { validatedPhotos.count }
    var invalidCount: Int { invalidPhotos.count }
    var processingFailureCount: Int { failedPhotos.count }
    var hasProcessingFailures: Bool { !failedPhotos.isEmpty }

    /// Enough photos show a person for the analysis to run (on `validatedPhotos` only).
    var hasEnoughValidPhotos: Bool { validCount >= HumanSubjectValidator.minimumValidPhotos }

    func status(of photoID: UUID) -> HumanSubjectStatus? { statuses[photoID] }

    init(sourcePhotos: [PhotoItem], statuses: [UUID: HumanSubjectStatus]) {
        var valid: [PhotoItem] = []
        var invalid: [PhotoItem] = []
        var failed: [PhotoItem] = []
        for photo in sourcePhotos {
            switch statuses[photo.id] {
            case .valid?: valid.append(photo)
            case .noHumanSubject?: invalid.append(photo)
            // Not checked at all counts as a processing failure, never as "no person".
            case .imageLoadFailed?, .visionFailed?, nil: failed.append(photo)
            }
        }
        self.sourcePhotos = sourcePhotos
        self.validatedPhotos = valid
        self.invalidPhotos = invalid
        self.failedPhotos = failed
        self.statuses = statuses
    }

    // MARK: Warning copy

    var warningTitle: String {
        hasProcessingFailures ? "Some Photos Couldn't Be Checked" : "Not Enough Photos with People"
    }

    var warningMessage: String {
        let found = "We found only \(validCount) \(validCount == 1 ? "photo" : "photos") containing people."
        let required = "At least \(HumanSubjectValidator.minimumValidPhotos) valid photos are required to analyze your photography style."
        guard hasProcessingFailures else {
            return "\(found) Please add more photos with visible people. \(required)"
        }
        let failures = processingFailureCount
        return "\(found) \(failures) \(failures == 1 ? "photo" : "photos") couldn't be checked. Try again, or add more photos with visible people. \(required)"
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

        let hasBody = (bodyRequest.results ?? []).contains {
            $0.confidence >= minimumConfidence
                && $0.boundingBox.width >= minimumBodySide && $0.boundingBox.height >= minimumBodySide
        }
        if hasBody { return .valid }
        let hasFace = (faceRequest.results ?? []).contains {
            $0.confidence >= minimumConfidence
                && $0.boundingBox.width >= minimumFaceSide && $0.boundingBox.height >= minimumFaceSide
        }
        return hasFace ? .valid : .noHumanSubject
    }
}
