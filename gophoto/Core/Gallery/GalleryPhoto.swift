//
//  Galleryphotos.swift
//  gophoto
//
//  Created by Reynard Setiawan on 12/10/26.
//
//  For photo taken in the app. Stores only the Photos ID, never the image.
//

import Foundation
import SwiftData

@Model
final class GalleryPhoto {
    /// assetID to store localidentifier of photos from iPhone Photos Library
    @Attribute(.unique) var assetID: String

    /// To determine photos taken from which preset, help to filter in gallery, null/nil if preset is deleted
    var presetID: UUID?

    var createdAt: Date

    init(assetID: String, presetID: UUID? = nil, createdAt: Date = .now) {
        self.assetID = assetID
        self.presetID = presetID
        self.createdAt = createdAt
    }
}
