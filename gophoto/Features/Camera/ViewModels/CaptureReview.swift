//
//  CaptureReview.swift
//  gophoto
//
//  The photo just taken, waiting in the review screen.
//

import CoreGraphics
import Foundation
import UIKit

struct CaptureReview: Identifiable {
    /// Where the person was at the shutter, for the crop modes.
    nonisolated struct CropPlan: Sendable {
        let person: CGRect
        let target: CGRect
        let roll: Double
        let megapixels: Double?
    }

    let id: UUID
    let photo: CapturedPhoto
    let cropPlan: CropPlan?
    /// Upright enhanced photo; nil while enhancing or if the enhance failed.
    var enhanced: UIImage?
    var isEnhancing = true
    /// Why Save failed, shown on the review screen.
    var saveError: String?
}
