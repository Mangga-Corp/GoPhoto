//
//  AppDatabase.swift
//  gophoto
//
//  Created by Reynard Setiawan on 13/10/26.
//
//  One local database for the whole app.
//  MyApp hands it to SwiftUI (@Query); stores write through its mainContext.
//  Same container on both sides → the gallery updates as soon as a photo is saved.
//

import SwiftData

enum AppDatabase {
    static let container: ModelContainer = {
        do {
            // Add new @Model types to this list (e.g. Preset, PresetPhoto)
            return try ModelContainer(for: GalleryPhoto.self)
        } catch {
            fatalError("Could not create the local database: \(error)")
        }
    }()
}
