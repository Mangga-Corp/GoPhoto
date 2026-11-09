//
//  ReplayLibrary.swift
//  gophoto
//
//  appMode 2 testing: imported test videos (copied into the app: Documents/ReplayVideos) and the
//  replay outputs (Documents/GuideLogs/Replay: run JSON, summary CSV, test frames). Nothing here
//  touches the photo library.
//
import CoreImage
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated enum ReplayLibrary {
    static var videos: URL { URL.documentsDirectory.appending(path: "ReplayVideos", directoryHint: .isDirectory) }
    static var results: URL { GuideLogger.directory.appending(path: "Replay", directoryHint: .isDirectory) }
    static var frames: URL { results.appending(path: "frames", directoryHint: .isDirectory) }
    static var summaryCSV: URL { results.appending(path: "replay-summary.csv") }

    /// Copies a picked file into the app (a security-scoped file from Files is only readable now).
    static func importFile(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try copyIn(url)
    }

    static func copyIn(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        var destination = videos.appending(path: url.lastPathComponent)
        if destination.standardizedFileURL == url.standardizedFileURL { return destination }
        var n = 1
        while FileManager.default.fileExists(atPath: destination.path()) {
            n += 1
            destination = videos.appending(path: "\(url.deletingPathExtension().lastPathComponent)-\(n).\(url.pathExtension)")
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }

    /// "Save test frame": the frame as JPEG in the replay results (not the photo library).
    static func saveFrame(_ frame: ReplayFrame, runID: String) throws -> URL {
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        let url = frames.appending(path: String(format: "%@-t%07.3f.jpg", runID, frame.mediaTime))
        let image = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let context = CIContext()
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                    options: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        return url
    }
}

/// A video picked in Photos, copied into the app.
nonisolated struct ReplayMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            ReplayMovie(url: try ReplayLibrary.copyIn(received.file))
        }
    }
}
