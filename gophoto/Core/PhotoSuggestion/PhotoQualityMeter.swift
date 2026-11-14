import Photos
import Vision
import UIKit

nonisolated struct PhotoQuality: Sendable {
    let assetID: String
    let isFavorite: Bool
    let creationDate: Date?
    /// Vision face capture quality 0–1 for the chosen face; nil when it could not be measured.
    let faceQuality: Float?
    /// Vision aesthetics overall score −1…1; nil when it could not be measured.
    let aesthetic: Float?
    let isUtility: Bool
}

nonisolated enum PhotoQualityGate {
    static let minimumFaceQuality: Float = 0.40
    static let minimumAesthetic: Float = -0.5

    /// Quality only, never taste: drops screenshots, blurry or badly lit faces, and junk.
    static func passes(_ quality: PhotoQuality) -> Bool {
        if quality.isUtility { return false }
        if let face = quality.faceQuality, face < minimumFaceQuality { return false }
        if let aesthetic = quality.aesthetic, aesthetic < minimumAesthetic { return false }
        return true
    }

    /// Favourites first, then sharper faces, then newest. Ties are deterministic.
    static func rank(_ qualities: [PhotoQuality]) -> [PhotoQuality] {
        qualities.sorted { a, b in
            if a.isFavorite != b.isFavorite { return a.isFavorite }
            let faceA = a.faceQuality ?? 0, faceB = b.faceQuality ?? 0
            if faceA != faceB { return faceA > faceB }
            let dateA = a.creationDate ?? .distantPast, dateB = b.creationDate ?? .distantPast
            if dateA != dateB { return dateA > dateB }
            return a.assetID < b.assetID
        }
    }
}

nonisolated protocol PhotoQualityMetering: Sendable {
    func measure(_ photos: [PersonPhoto]) async -> [PhotoQuality]
}

nonisolated final class PhotoQualityMeter: PhotoQualityMetering {
    @concurrent
    func measure(_ photos: [PersonPhoto]) async -> [PhotoQuality] {
        let assets = PhotoAssets.byID(photos.map(\.id))
        var qualities: [PhotoQuality] = []
        for photo in photos {
            var faceQuality: Float?
            var aesthetic: Float?
            var isUtility = false
            if let url = photo.thumbnailURL, let image = FaceCrop.thumbnail(at: url)?.cgImage {
                if let scores = try? await CalculateImageAestheticsScoresRequest().perform(on: image) {
                    aesthetic = scores.overallScore
                    isUtility = scores.isUtility
                }
                if let face = photo.faceBounds, let crop = FaceCrop.image(at: url, face: face)?.cgImage,
                   let faces = try? await DetectFaceCaptureQualityRequest().perform(on: crop) {
                    faceQuality = faces.compactMap { $0.captureQuality?.score }.max()  // VERIFY property name
                }
            }
            let asset = assets[photo.id]
            qualities.append(PhotoQuality(assetID: photo.id, isFavorite: asset?.isFavorite ?? false,
                                          creationDate: asset?.creationDate, faceQuality: faceQuality,
                                          aesthetic: aesthetic, isUtility: isUtility))
        }
        return qualities
    }
}

nonisolated enum PhotoAssets {
    static func byID(_ ids: [String]) -> [String: PHAsset] {
        var found: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in found[asset.localIdentifier] = asset }
        return found
    }

    /// Assets in the order of `ids`; missing ones are skipped.
    static func ordered(_ ids: [String]) -> [PHAsset] {
        let found = byID(ids)
        return ids.compactMap { found[$0] }
    }
}
