//
//  FaceGroupingService.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//

import CoreGraphics
import Foundation
import MediaIntelligence
import Photos
import UIKit

nonisolated struct PersonFace: Sendable, Hashable {
    let assetID: String
    let entityID: String
    /// Normalized 0–1, origin top-left (project convention).
    let bounds: CGRect

    /// A face the analyzer could not assign to anyone.
    static let unassigned = ""

    var area: Double { Double(bounds.width * bounds.height) }
}

nonisolated struct PersonGroup: Identifiable, Sendable {
    let id: String
    let faces: [PersonFace]

    var assetIDs: Set<String> { Set(faces.map(\.assetID)) }
    var cover: PersonFace? { faces.max { $0.area < $1.area } }
}

nonisolated struct FaceGroupingProgress: Sendable, Equatable {
    let photosChecked: Int
    let facesFound: Int
}

nonisolated struct FaceGroupingResult: Sendable {
    /// Largest group first.
    let groups: [PersonGroup]
    /// Every face found in a photo, by photo. Used by the solo / main-focus filter.
    let facesByAsset: [String: [PersonFace]]
    /// 512 px copies on disk, used for face crops until `clear()`.
    let thumbnailURLs: [String: URL]
    let photosChecked: Int
}

nonisolated enum FaceGroupingError: Error {
    case unavailable
}

nonisolated protocol FaceGrouping: Sendable {
    func scan(maxFaces: Int, maxPhotos: Int,
              onProgress: @escaping @Sendable (FaceGroupingProgress) -> Void) async throws -> FaceGroupingResult
    /// Deletes every face and thumbnail this scan produced.
    func clear() async
}

@available(iOS 27.0, *)
nonisolated final class FaceGroupAnalyzerService: FaceGrouping {
    static let thumbnailSide: CGFloat = 512
    static let batchSize = 25
    /// No new photos are added after this; the rest of the budget goes to clustering.
    static let scanTimeLimit: Duration = .seconds(25)

    private static let directory = URL.cachesDirectory
        .appending(path: "FaceGroupData", directoryHint: .isDirectory)
    private static let imagesDirectory = directory
        .appending(path: "images", directoryHint: .isDirectory)

    /// One analyzer per process: a second live instance crashes the framework.
    private static let analyzer: FaceGroupAnalyzer? = {
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        return try? FaceGroupAnalyzer(workingDirectory: directory)
    }()

    /// Call once at app launch, before any analyzer exists: removes data a crash left behind.
    static func purgeLeftovers() async {
        try? await FaceGroupAnalyzer.purge(workingDirectory: directory)
        try? FileManager.default.removeItem(at: imagesDirectory)

    }

    @concurrent
    func scan(maxFaces: Int, maxPhotos: Int,
              onProgress: @escaping @Sendable (FaceGroupingProgress) -> Void) async throws -> FaceGroupingResult {
        guard let analyzer = Self.analyzer else { throw FaceGroupingError.unavailable }
        await clear()

        let assets = Self.candidateAssets()
        let total = min(assets.count, maxPhotos)
        var thumbnailURLs: [String: URL] = [:]
        var facesFound = 0
        var index = 0
        let clock = ContinuousClock()
        let deadline = clock.now + Self.scanTimeLimit

        while index < total, facesFound < maxFaces, clock.now < deadline {
            try Task.checkCancellation()
            var batch: [MediaIntelligenceImageAsset] = []
            while batch.count < Self.batchSize, index < total {
                let asset = assets.object(at: index)
                index += 1
                guard let url = await Self.exportThumbnail(for: asset) else { continue }
                thumbnailURLs[asset.localIdentifier] = url
                batch.append(MediaIntelligenceImageAsset(id: .init(asset.localIdentifier), kind: .url(url)))
            }
            guard !batch.isEmpty else { continue }
            for try await (_, faces) in try await analyzer.insertOrUpdateAssets(batch) {
                facesFound += faces.count
            }
            onProgress(FaceGroupingProgress(photosChecked: index, facesFound: facesFound))
        }

        try Task.checkCancellation()
        if await analyzer.state == .stale {
            try await analyzer.update(subprogress: nil)
        }

        var groups: [PersonGroup] = []
        for try await (entityID, faces) in analyzer.allFacesByEntityID {
            let id = String(describing: entityID)
            groups.append(PersonGroup(id: id, faces: faces.map { Self.personFace($0, entityID: id) }))
        }
        groups.sort { ($0.assetIDs.count, $0.id) > ($1.assetIDs.count, $1.id) }

        var facesByAsset: [String: [PersonFace]] = [:]
        for try await face in analyzer.allFaces {
            let id = face.entityID.map { String(describing: $0) } ?? PersonFace.unassigned
            let converted = Self.personFace(face, entityID: id)
            facesByAsset[converted.assetID, default: []].append(converted)
        }

        return FaceGroupingResult(groups: groups, facesByAsset: facesByAsset,
                                  thumbnailURLs: thumbnailURLs, photosChecked: index)
    }

    @concurrent
    func clear() async {
        try? await Self.analyzer?.deleteAllAssets()
        try? FileManager.default.removeItem(at: Self.imagesDirectory)
        try? FileManager.default.createDirectory(at: Self.imagesDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Photos

    private static func candidateAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let skipped = PHAssetMediaSubtype.photoScreenshot.rawValue | PHAssetMediaSubtype.photoPanorama.rawValue
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", skipped)
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    private static func exportThumbnail(for asset: PHAsset) async -> URL? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let side = CGSize(width: thumbnailSide, height: thumbnailSide)
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: side,
                                                  contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let data = image?.jpegData(compressionQuality: 0.9) else { return nil }
        let url = imagesDirectory.appending(path: fileName(for: asset.localIdentifier) + ".jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// localIdentifiers contain "/" → safe file name.
    private static func fileName(for assetID: String) -> String {
        Data(assetID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    // MARK: - Conversion

    private static func personFace(_ face: FaceGroupAnalyzer.Face, entityID: String) -> PersonFace {
        let box = face.bounds
        let topLeft = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        return PersonFace(assetID: face.assetID.rawValue,
                          entityID: entityID, bounds: topLeft)
    }

}
