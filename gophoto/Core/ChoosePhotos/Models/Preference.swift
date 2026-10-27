//
//  Preference.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import Foundation

struct Preference {
    let id: UUID
    var name: String
    var photos: [PhotoItem]
    /// What the AI learned from the photos (camera targets). Nil until analysed.
    var analysis: PresetAnalysis?

    init(id: UUID = UUID(), name: String, photos: [PhotoItem] = [], analysis: PresetAnalysis? = nil) {
        self.id = id
        self.name = name
        self.photos = photos
        self.analysis = analysis
    }
}
