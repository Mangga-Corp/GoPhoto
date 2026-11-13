//
//  Preference.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

struct Preference: Identifiable {
    let id: UUID
    var name: String
    var photos: [PhotoItem]
    /// What the AI learned from the photos (camera targets). Nil until analysed.
    /// For a custom preference: derived from `customStyle`, never analysed.
    var analysis: PresetAnalysis?
    /// Set for a preference made from a subject placement and camera angle instead of photos.
    let customStyle: CustomPreferenceStyle?

    /// Made from a chosen placement and angle: it has no reference photos to edit or analyse.
    var isCustom: Bool { customStyle != nil }

    init(id: UUID = UUID(), name: String, photos: [PhotoItem] = [], analysis: PresetAnalysis? = nil) {
        self.id = id
        self.name = name
        self.photos = photos
        self.analysis = analysis
        self.customStyle = nil
    }

    /// A custom preference: its camera targets come from `style`.
    init(id: UUID = UUID(), name: String, customStyle: CustomPreferenceStyle) {
        self.id = id
        self.name = name
        self.photos = []
        self.analysis = CustomPresetAnalysisFactory.makeAnalysis(for: customStyle)
        self.customStyle = customStyle
    }
}
