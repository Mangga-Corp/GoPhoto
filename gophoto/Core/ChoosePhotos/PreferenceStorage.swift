//
//  PreferenceStorage.swift
//  gophoto
//
//  Created by Sebastian Darren on 19/10/26.
//

import UIKit
import os

private enum PreferenceStorageError: LocalizedError {
    case photoEncodingFailed
    case preferenceNotFound
    case photoReadFailed

    var errorDescription: String? {
        switch self {
        case .photoEncodingFailed: "A selected photo could not be saved."
        case .preferenceNotFound: "The saved preference could not be found."
        case .photoReadFailed: "A saved preference photo could not be read."
        }
    }
}

/// Saves preferences (names + photos) in the app's Application Support folder.
final class PreferencesStorage {
    private struct Snapshot: Codable {
        struct Entry: Codable {
            let id: UUID
            let name: String
            let photoIDs: [UUID]
            var analysis: PresetAnalysis?
            /// EXIF 35 mm-equivalent focal length per photo (`UUID.uuidString`), when known.
            var focals: [String: Double]?

            init(id: UUID, name: String, photoIDs: [UUID], analysis: PresetAnalysis?, focals: [String: Double]?) {
                self.id = id; self.name = name; self.photoIDs = photoIDs; self.analysis = analysis
                self.focals = focals
            }

            /// An unreadable analysis is dropped (the preset is analysed again), the preset is kept.
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(UUID.self, forKey: .id)
                name = try c.decode(String.self, forKey: .name)
                photoIDs = try c.decode([UUID].self, forKey: .photoIDs)
                analysis = try? c.decodeIfPresent(PresetAnalysis.self, forKey: .analysis)
                focals = try? c.decodeIfPresent([String: Double].self, forKey: .focals)
            }
        }
        var entries: [Entry]
        var selectedID: UUID?
    }

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "gophoto.preferences.storage", qos: .utility)
    private let root: URL
    private let logger = Logger(subsystem: "co.mango.gophoto", category: "preferences.storage")

    init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent(Self.directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
    }

    #if DEBUG
    /// Debug builds launched with `-GoPhotoFixtureStore <name>` use a separate folder, so fixture
    /// data never touches the real preferences. Without the argument: the normal folder.
    private static var directoryName: String {
        DebugFixtures.storeName.map { "PreferencesFixtures/\($0)" } ?? "Preferences"
    }
    #else
    private static let directoryName = "Preferences"
    #endif

    private var photosURL: URL { root.appendingPathComponent("photos", isDirectory: true) }
    private var indexURL: URL { root.appendingPathComponent("index.json") }
    private func photoURL(_ id: UUID) -> URL { photosURL.appendingPathComponent("\(id.uuidString).jpg") }

    func load() -> (preferences: [Preference], selectedID: UUID?) {
        guard let data = try? Data(contentsOf: indexURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return ([], nil) }
        let referencedFiles = Set(snapshot.entries.flatMap(\.photoIDs).map { photoURL($0).lastPathComponent })
        removeUnreferencedPhotoFiles(keeping: referencedFiles)
        let preferences = snapshot.entries.map { entry in
            let photos = unique(entry.photoIDs).compactMap { id -> PhotoItem? in
                guard let image = UIImage(contentsOfFile: photoURL(id).path) else { return nil }
                return PhotoItem(id: id, image: image, focalLength35mm: entry.focals?[id.uuidString])
            }
            return Preference(id: entry.id, name: entry.name, photos: photos, analysis: entry.analysis)
        }
        return (preferences, snapshot.selectedID)
    }

    func loadPreference(
        id: UUID,
        completion: @escaping (Result<Preference, Error>) -> Void
    ) {
        ioQueue.async { [self] in
            do {
                completion(.success(try loadPreferenceSynchronously(id: id)))
            } catch {
                logger.error("Could not load persisted preference \(id): \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
            }
        }
    }

    /// Runs in the background so picking many photos doesn't freeze the UI. New image files are
    /// written before the index is atomically replaced; failed writes remove files created by
    /// this save, leaving the previous index and preference set intact.
    func save(
        _ preferences: [Preference],
        selectedID: UUID?,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        ioQueue.async { [self] in
            do {
                try saveSynchronously(preferences, selectedID: selectedID)
                completion?(.success(()))
            } catch {
                logger.error("Could not save preferences: \(error.localizedDescription, privacy: .public)")
                completion?(.failure(error))
            }
        }
    }

    private func saveSynchronously(_ preferences: [Preference], selectedID: UUID?) throws {
        try fileManager.createDirectory(at: photosURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let uniquePhotosByID = preferences.reduce(into: [UUID: PhotoItem]()) { result, preference in
            for photo in preference.photos where result[photo.id] == nil {
                result[photo.id] = photo
            }
        }
        let entries = preferences.map { preference -> Snapshot.Entry in
            let photos = unique(preference.photos)
            let focals = photos.reduce(into: [String: Double]()) { map, photo in
                if let focal = photo.focalLength35mm { map[photo.id.uuidString] = focal }
            }
            return .init(id: preference.id, name: preference.name, photoIDs: photos.map(\.id),
                         analysis: preference.analysis, focals: focals.isEmpty ? nil : focals)
        }
        let snapshot = Snapshot(entries: entries, selectedID: selectedID)
        let indexData = try JSONEncoder().encode(snapshot)
        let usedFiles = Set(uniquePhotosByID.keys.map { photoURL($0).lastPathComponent })
        var filesCreatedByThisSave: [URL] = []

        do {
            for photo in uniquePhotosByID.values {
                let destination = photoURL(photo.id)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                guard let imageData = photo.image.jpegData(compressionQuality: 0.85) else {
                    throw PreferenceStorageError.photoEncodingFailed
                }
                try imageData.write(to: destination, options: .atomic)
                filesCreatedByThisSave.append(destination)
            }

            try indexData.write(to: indexURL, options: .atomic)
        } catch {
            for url in filesCreatedByThisSave {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    logger.error("Could not remove an uncommitted photo file: \(error.localizedDescription, privacy: .public)")
                }
            }
            throw error
        }

        removeUnreferencedPhotoFiles(keeping: usedFiles)
    }

    private func loadPreferenceSynchronously(id: UUID) throws -> Preference {
        let data = try Data(contentsOf: indexURL)
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        guard let entry = snapshot.entries.first(where: { $0.id == id }) else {
            throw PreferenceStorageError.preferenceNotFound
        }

        var seen = Set<UUID>()
        let photoIDs = entry.photoIDs.filter { seen.insert($0).inserted }
        let photos = try photoIDs.map { photoID -> PhotoItem in
            guard let image = UIImage(contentsOfFile: photoURL(photoID).path) else {
                throw PreferenceStorageError.photoReadFailed
            }
            return PhotoItem(id: photoID, image: image, focalLength35mm: entry.focals?[photoID.uuidString])
        }
        return Preference(id: entry.id, name: entry.name, photos: photos, analysis: entry.analysis)
    }

    private func removeUnreferencedPhotoFiles(keeping referencedFiles: Set<String>) {
        guard let files = try? fileManager.contentsOfDirectory(atPath: photosURL.path) else { return }
        for file in files where !referencedFiles.contains(file) {
            do {
                try fileManager.removeItem(at: photosURL.appendingPathComponent(file))
            } catch {
                logger.error("Could not remove an unreferenced photo file: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func unique(_ photos: [PhotoItem]) -> [PhotoItem] {
        var seen = Set<UUID>()
        return photos.filter { seen.insert($0.id).inserted }
    }
}
