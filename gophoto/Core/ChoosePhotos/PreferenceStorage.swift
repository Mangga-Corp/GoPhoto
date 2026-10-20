//
//  PreferenceStorage.swift
//  gophoto
//
//  Created by Sebastian Darren on 19/10/26.
//

import UIKit

/// Saves preferences (names + photos) in the app's Application Support folder.
final class PreferencesStorage {
    private struct Snapshot: Codable {
        struct Entry: Codable { let id: UUID; let name: String; let photoIDs: [UUID] }
        var entries: [Entry]
        var selectedID: UUID?
    }

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "gophoto.preferences.storage", qos: .utility)
    private let root: URL

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("Preferences", isDirectory: true)
        try? fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
    }

    private var photosURL: URL { root.appendingPathComponent("photos", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private func photoURL(_ id: UUID) -> URL { photosURL.appendingPathComponent("\(id.uuidString).jpg") }

    func load() -> (preferences: [Preference], selectedID: UUID?) {
        guard let data = try? Data(contentsOf: indexURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return ([], nil) }
        let preferences = snapshot.entries.map { entry in
            let photos = entry.photoIDs.compactMap { id -> PhotoItem? in
                guard let image = UIImage(contentsOfFile: photoURL(id).path) else { return nil }
                return PhotoItem(id: id, image: image)
            }
            return Preference(id: entry.id, name: entry.name, photos: photos)
        }
        return (preferences, snapshot.selectedID)
    }

    /// Runs in the background so picking many photos doesn't freeze the UI.
    func save(_ preferences: [Preference], selectedID: UUID?) {
        ioQueue.async { [self] in
            let photos = preferences.flatMap(\.photos)
            for photo in photos {
                let url = photoURL(photo.id)
                guard !fileManager.fileExists(atPath: url.path),
                      let data = photo.image.jpegData(compressionQuality: 0.85) else { continue }
                try? data.write(to: url, options: .atomic)
            }
            // Remove photo files that no longer belong to any preference.
            let used = Set(photos.map { photoURL($0.id).lastPathComponent })
            for file in (try? fileManager.contentsOfDirectory(atPath: photosURL.path)) ?? [] where !used.contains(file) {
                try? fileManager.removeItem(at: photosURL.appendingPathComponent(file))
            }
            let snapshot = Snapshot(
                entries: preferences.map { .init(id: $0.id, name: $0.name, photoIDs: $0.photos.map(\.id)) },
                selectedID: selectedID)
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: indexURL, options: .atomic) }
        }
    }
}
