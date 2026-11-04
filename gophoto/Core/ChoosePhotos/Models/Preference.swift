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
    /// Posture the user set by hand per photo (`PhotoItem.id.uuidString` → `Posture.rawValue`,
    /// "standing" / "sitting"). Beats what the app reads from the photo, and survives a new analysis.
    var postureOverrides: [String: String]

    init(id: UUID = UUID(), name: String, photos: [PhotoItem] = [], analysis: PresetAnalysis? = nil,
         postureOverrides: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.photos = photos
        self.analysis = analysis
        self.postureOverrides = postureOverrides
    }
}
