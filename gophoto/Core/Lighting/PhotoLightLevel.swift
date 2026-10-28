//
//  PhotoLightLevel.swift
//  gophoto
//
//  Core layer: how bright the user's reference photos are, read once when a preset is analysed.
//  Reuses the enhancer's tone measurement, so "bright" means the same thing in both places.
//

import CoreImage
import UIKit

nonisolated enum PhotoLightLevel {

    private static let context = CIContext()

    /// Median mean luminance (0...1) of the photos; nil when none could be read.
    static func median(of images: [UIImage]) -> Double? {
        let levels = images.compactMap { image -> Double? in
            guard let ciImage = CIImage(image: image) else { return nil }
            return PhotoStatistics.measure(ciImage, faces: [], context: context).meanLuminance
        }.sorted()
        guard !levels.isEmpty else { return nil }
        let mid = levels.count / 2
        return levels.count.isMultiple(of: 2) ? (levels[mid - 1] + levels[mid]) / 2 : levels[mid]
    }
}
