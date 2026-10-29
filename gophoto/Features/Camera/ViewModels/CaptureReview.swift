//
//  CaptureReview.swift
//  gophoto
//
//  The photo just taken, waiting in the review screen.
//

import UIKit

struct CaptureReview: Identifiable {
    let id: UUID
    let photo: CapturedPhoto
    /// Upright enhanced photo; nil while enhancing or if the enhance failed.
    var enhanced: UIImage?
    var isEnhancing = true
    /// Why Save failed, shown on the review screen.
    var saveError: String?
}
