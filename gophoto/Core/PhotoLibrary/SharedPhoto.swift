//
//  SharedPhoto.swift
//  gophoto
//
//  Created by Reynard Setiawan on 15/10/26.
//
//  A gallery photo that ShareLink can share (DBM-79).
//  Offers two formats; iOS gives each share target the FIRST one it supports:
//  1. HEIC (iPhone's original) → AirDrop, Messages, Files…
//  2. JPEG (fallback)          → apps/services that can't open HEIC
//  The image is read from Photos only when the user picks a target.
//

import CoreTransferable
import UniformTypeIdentifiers

nonisolated struct SharedPhoto: Transferable {
    let assetID: String

    static var transferRepresentation: some TransferRepresentation {
        // 1. Preferred: HEIC (original, untouched if it already is HEIC)
        DataRepresentation(exportedContentType: .heic) { photo in
            try await PhotoExport.data(for: photo.assetID, as: .heic)
        }
        .suggestedFileName("GoPhoto.heic")

        // 2. Fallback: JPEG (opens everywhere)
        DataRepresentation(exportedContentType: .jpeg) { photo in
            try await PhotoExport.data(for: photo.assetID, as: .jpeg)
        }
        .suggestedFileName("GoPhoto.jpg")
    }
}
