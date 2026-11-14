//
//  FaceFingerprint.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//
import Photos
import UIKit
import Vision

nonisolated struct FaceSample: @unchecked Sendable {
    let assetID: String
    let faceCrop: CGImage
    let faceHeightShare: Double
    let fingerprint: FeaturePrintObservation
}

nonisolated protocol FaceFingerprinting: Sendable {
    func collectFaces(maxFaces: Int, maxPhotos: Int,
                      onProgress: @escaping @Sendable (Int) -> Void) async -> [FaceSample]
}

nonisolated final class FaceFingerprinter: FaceFingerprinting {
    static let thumbnailSide: CGFloat = 512
    static let minimumFaceHeight = 0.03
    static let cropMargin = 0.3

    @concurrent
    func collectFaces(maxFaces: Int = 300, maxPhotos: Int = 1500,
                      onProgress: @escaping @Sendable (Int) -> Void) async -> [FaceSample] {
        let assets = Self.candidateAssets()
        var samples: [FaceSample] = []
        for index in 0..<min(assets.count, maxPhotos) {
            if Task.isCancelled || samples.count >= maxFaces { break }
            let asset = assets.object(at: index)
            if let image = await Self.thumbnail(for: asset) {
                samples += await Self.faces(in: image, assetID: asset.localIdentifier)
            }
            onProgress(index + 1)
        }
        return samples
    }

    private static func candidateAssets() -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let skipped = PHAssetMediaSubtype.photoScreenshot.rawValue | PHAssetMediaSubtype.photoPanorama.rawValue
        options.predicate = NSPredicate(format: "(mediaSubtypes & %d) == 0", skipped)
        return PHAsset.fetchAssets(with: .image, options: options)
    }

    private static func thumbnail(for asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        let size = CGSize(width: thumbnailSide, height: thumbnailSide)
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size,
                                                  contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        guard let image else { return nil }
        if image.imageOrientation == .up { return image.cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: image.size, format: format)
            .image { _ in image.draw(at: .zero) }
            .cgImage
    }

    private static func faces(in image: CGImage, assetID: String) async -> [FaceSample] {
        guard let observations = try? await DetectFaceRectanglesRequest().perform(on: image) else { return [] }
        let width = Double(image.width)
        let height = Double(image.height)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        var samples: [FaceSample] = []
        for face in observations {
            let box = face.boundingBox.cgRect
            guard box.height >= minimumFaceHeight else { continue }
            let pixels = CGRect(x: box.minX * width, y: (1 - box.maxY) * height,
                                width: box.width * width, height: box.height * height)
                .insetBy(dx: -box.width * width * cropMargin, dy: -box.height * height * cropMargin)
                .intersection(bounds)
                .integral
            guard let crop = image.cropping(to: pixels),
                  let fingerprint = try? await GenerateImageFeaturePrintRequest().perform(on: crop) else { continue }
            samples.append(FaceSample(assetID: assetID, faceCrop: crop,
                                      faceHeightShare: box.height, fingerprint: fingerprint))
        }
        return samples
    }
}
