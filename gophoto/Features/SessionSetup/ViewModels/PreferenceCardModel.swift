//
//  PreferenceCardModel.swift
//  gophoto
//
//  What one Preference Selection card shows, made only from the saved preference and its
//  analysis. A trait the analysis didn't establish is left out, never filled with a placeholder.
//

import UIKit

struct PreferenceCardModel: Identifiable {
    enum Availability: Equatable {
        /// A session can start with this preference.
        case available
        /// Not usable yet: its first analysis is running.
        case analyzing
        /// Not usable: why, in a short line for the card.
        case unavailable(String)
    }

    let id: UUID
    let name: String
    /// The style tagline, or the photo count when the analysis doesn't name a style.
    let summary: String
    /// Up to two "Category: Value" chips, each backed by the analysis.
    let chips: [String]
    /// The first reference photo, or nil (the card shows a neutral placeholder).
    let thumbnail: UIImage?
    /// Changes when the thumbnail's source photo changes (thumbnail cache key).
    let thumbnailKey: String
    let availability: Availability
    /// A re-analysis is running (the previous result still guides the camera).
    let isUpdating: Bool
    /// The preference used to start the most recent session.
    let isLastUsed: Bool
    /// Set for a custom preference (placement + angle): the card draws it instead of a photo.
    let customStyle: CustomPreferenceStyle?

    var isAvailable: Bool { availability == .available }
    /// Custom preferences have no reference photos, so their photos can't be edited.
    var canEditPhotos: Bool { customStyle == nil }

    static let maxChips = 2

    /// - Parameter needsMorePersonPhotos: its latest run stopped because too few photos show a person.
    init(preference: Preference, availability: Result<Void, PhotoSessionError>, isAnalyzing: Bool,
         isLastUsed: Bool, needsMorePersonPhotos: Bool = false) {
        id = preference.id
        name = preference.name
        self.isLastUsed = isLastUsed
        customStyle = preference.customStyle
        let photo = preference.photos.first
        thumbnail = photo?.image
        thumbnailKey = "\(preference.id.uuidString)-\(photo?.id.uuidString ?? "none")"

        switch availability {
        case .success:
            self.availability = .available
        case .failure where isAnalyzing:
            self.availability = .analyzing
        case .failure(let error):
            self.availability = .unavailable(needsMorePersonPhotos
                ? "Needs at least \(HumanSubjectValidator.minimumValidPhotos) photos showing only one person. Edit photos to add more."
                : Self.reason(for: error, preference: preference))
        }
        isUpdating = isAnalyzing && self.availability == .available

        let analysis = preference.analysis
        let style = StyleSummary(analysis: analysis, photos: preference.analyzedPhotos)
        switch self.availability {
        case .available where preference.customStyle != nil:
            summary = "Custom preference"
            chips = preference.customStyle.map(Self.chips(for:)) ?? []
        case .available:
            let count = preference.analyzedPhotos.count
            summary = style?.tagline ?? "Based on \(count) reference \(count == 1 ? "photo" : "photos")"
            chips = analysis.map { Array(Self.chips(for: $0, photos: preference.analyzedPhotos).prefix(Self.maxChips)) } ?? []
        case .analyzing:
            summary = "Analyzing your reference photos…"
            chips = []
        case .unavailable(let reason):
            summary = reason
            chips = []
        }
    }

    private static func reason(for error: PhotoSessionError, preference: Preference) -> String {
        if preference.photos.isEmpty && !preference.isCustom { return "No reference photos. Edit to add some." }
        switch error {
        case .analysisUnavailable: return "Not analyzed yet. Edit photos to try again."
        case .analysisFailed: return "Analysis failed. Edit photos to try again."
        case .noShotVariant: return "Couldn't read the framing in these photos."
        case .preferenceNotFound: return "This preference no longer exists."
        }
    }

    // MARK: Chips

    /// A custom preference's two choices.
    static func chips(for style: CustomPreferenceStyle) -> [String] {
        ["Placement: \(style.placement.shortTitle)", "Angle: \(style.angle.shortTitle)"]
    }

    /// Lighting, angle, framing, placement, in that order, each only when the analysis has it.
    /// Thresholds match the style card (`StyleSummary`) so both screens make the same claims.
    static func chips(for analysis: PresetAnalysis, photos: [PhotoItem]) -> [String] {
        var chips: [String] = []

        if let level = analysis.lightLevel {
            let light: String = switch LightPreference(level: level).style {
            case .bright: "Bright"
            case .balanced: "Balanced"
            case .moody: "Moody"
            }
            chips.append("Lighting: \(light)")
        }

        let side = analysis.eyeSide.flatMap(PresetAnalysis.EyeSide.init(rawValue:))
        switch analysis.eyeSideSource.flatMap(PresetAnalysis.EyeSideSource.init(rawValue:)) {
        case .taste?:
            if let side { chips.append(side == .below ? "Angle: Low" : "Angle: High") }
        case .mixed?:
            chips.append("Angle: Varied")
        case .default?, nil:
            break   // not learned from the photos: no claim
        }

        let shots = photos.compactMap { analysis.photoShotSizes?[$0.id.uuidString] }
            .compactMap(PresetAnalysis.ShotSize.init(rawValue:))
        if let top = PresetAnalysis.ShotSize.allCases.max(by: { a, b in
            shots.filter { $0 == a }.count < shots.filter { $0 == b }.count
        }), !shots.isEmpty,
           Double(shots.filter { $0 == top }.count) / Double(shots.count) >= StyleSummary.clearShare {
            chips.append("Framing: \(top.displayTitle)")
        }

        if let box = analysis.subjectBox, analysis.subjectPhotoCount > 0 {
            chips.append(box.midX < 0.4 || box.midX > 0.6 ? "Placement: Off-center" : "Placement: Center")
        }
        return chips
    }
}
