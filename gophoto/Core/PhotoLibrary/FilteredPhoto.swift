//
//  FilteredPhoto.swift
//  gophoto
//
//  A gallery photo with an AI Enhanced look, for ShareLink. The look is rendered at full
//  resolution only when the user picks a share target (the share sheet has "Save Image"), and the
//  photo in Photos is never changed. Metadata (date, lens, location) is kept.
//

import CoreTransferable
import UniformTypeIdentifiers

nonisolated struct FilteredPhoto: Transferable {
    let assetID: String
    let look: EnhancedLook

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { photo in
            try await photo.renderedJPEG()
        }
        .suggestedFileName("GoPhoto.jpg")
    }

    private func renderedJPEG() async throws -> Data {
        let source = try await PhotoExport.data(for: assetID, as: .jpeg)
        let look = look
        let output: Data? = await Task.detached(priority: .userInitiated) {
            CapturedPhotoEnhancing.enhance(source, look: look)
                .flatMap { CapturedPhotoEnhancing.file(for: $0, metadataFrom: source) }
        }.value
        guard let output else { throw PhotoExportError.unreadable }
        return output
    }
}
