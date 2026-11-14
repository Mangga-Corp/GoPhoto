//
//  CameraAspectRatio.swift
//  gophoto
//
//  The shape of the photo the camera frames and saves: 3:4 (default) or 9:16, portrait.
//
//  One coordinate system for everything: the camera frame (the `.photo` preset, rotated upright,
//  3:4 = `frameRatio`), in frame units with origin top-left. Person detection, the Phased engine
//  and `PhasedCrop` all work in it. A ratio narrower than the frame is its centred, full-height
//  band (`visibleRect`; 9:16 = the middle 75 % of the width). The preview shows exactly that band
//  (aspect fill), the overlays map between the preview box and frame units through it, and the
//  Auto crop is made inside it with the ratio's shape, so the saved photo shows what the preview
//  showed.
//

import CoreGraphics

nonisolated enum CameraAspectRatio: String, CaseIterable, Identifiable, Sendable {
    case threeFour
    case nineSixteen

    var id: String { rawValue }

    /// Width / height of the upright camera frame (same as `PhasedFrame.frameAspect`).
    static let frameRatio: Double = 3.0 / 4.0

    /// Width / height of the photo.
    var ratio: Double {
        switch self {
        case .threeFour: 3.0 / 4.0
        case .nineSixteen: 9.0 / 16.0
        }
    }

    /// The photo's exact pixel proportions (width units, height units).
    var units: (width: Int, height: Int) {
        switch self {
        case .threeFour: (3, 4)
        case .nineSixteen: (9, 16)
        }
    }

    var title: String {
        switch self {
        case .threeFour: "3:4"
        case .nineSixteen: "9:16"
        }
    }

    var accessibilityName: String {
        switch self {
        case .threeFour: "3 by 4"
        case .nineSixteen: "9 by 16"
        }
    }

    /// The part of the camera frame this ratio shows and saves (frame units, origin top-left).
    var visibleRect: CGRect {
        let width = min(1, ratio / Self.frameRatio)
        let height = min(1, Self.frameRatio / ratio)
        return CGRect(x: (1 - width) / 2, y: (1 - height) / 2, width: width, height: height)
    }

    /// The Auto crop's shape and allowed band for this ratio.
    var cropShape: PhasedCropShape {
        let band = visibleRect
        return PhasedCropShape(widthFactor: min(1, ratio / Self.frameRatio),
                               minX: Double(band.minX), maxX: Double(band.maxX))
    }

    /// The grid overlay's ratio (the grid fills the preview box, which already has this ratio).
    var gridAspect: CaptureAspect {
        switch self {
        case .threeFour: .fourThree
        case .nineSixteen: .sixteenNine
        }
    }

    /// The full frame shows as is (no change from the original 3:4 camera); narrower ratios
    /// always cut the frame, so their saved photo is always cropped to their exact shape.
    var showsWholeFrame: Bool { visibleRect == CGRect(x: 0, y: 0, width: 1, height: 1) }

    // MARK: Preview box ↔ frame units

    /// A point in the preview box (0...1 of the box, origin top-left) in frame units.
    func framePoint(fromPreview point: CGPoint) -> CGPoint {
        let band = visibleRect
        return CGPoint(x: band.minX + point.x * band.width, y: band.minY + point.y * band.height)
    }

    /// A rect in frame units in preview-box units (0...1 of the box; may run outside it).
    func previewRect(fromFrame rect: CGRect) -> CGRect {
        let band = visibleRect
        return CGRect(x: (rect.minX - band.minX) / band.width, y: (rect.minY - band.minY) / band.height,
                      width: rect.width / band.width, height: rect.height / band.height)
    }
}
