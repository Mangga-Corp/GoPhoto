//
//  PhotoExport.swift
//  gophoto
//
//  Created by Reynard Setiawan on 15/10/26.
//
//  Reads a photo from the Photos library for sharing (DBM-79), in the format
//  the share target asks for. Same idea as the Photos app's "Automatic" format:
//  original file if it already matches, otherwise converted (metadata kept).
//

import Photos
import ImageIO
import UniformTypeIdentifiers

nonisolated enum PhotoExportError: LocalizedError {
    case notFound
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notFound:   return "This photo is no longer in your library."
        case .unreadable: return "Couldn't read this photo. Please try again."
        }
    }
}

nonisolated enum PhotoExport {

    static func data(for assetID: String, as type: UTType) async throws -> Data {
        let original = try await originalData(for: assetID)
        if original.type.conforms(to: type) {
            return original.data
        }
        return try convert(original.data, to: type)
    }


    /// The file as stored in Photos (includes edits made in the Photos app)
    private static func originalData(for assetID: String) async throws -> (data: Data, type: UTType) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
            throw PhotoExportError.notFound
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current

        let result: (Data, String)? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, uti, _, _ in
                if let data, let uti {
                    continuation.resume(returning: (data, uti))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }

        guard let (data, uti) = result, let type = UTType(uti) else {
            throw PhotoExportError.unreadable
        }
        return (data, type)
    }

    private static func convert(_ data: Data, to type: UTType) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoExportError.unreadable
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw PhotoExportError.unreadable
        }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        CGImageDestinationAddImageFromSource(destination, source, 0, options)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoExportError.unreadable
        }
        return output as Data
    }
}
