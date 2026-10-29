import CoreGraphics
import Foundation

nonisolated struct LiveEnvironmentSignal: Sendable {
    let sampledAt: TimeInterval
    let width: Int
    let height: Int
    let environmentalMask: [UInt8]
    let supportedFraction: Double

    static let maximumAge: TimeInterval = 2
    static let minimumSupportedFraction = 0.5
    static let minimumRemovedContextFraction = 0.15

    func isReliable(at now: TimeInterval) -> Bool {
        now >= sampledAt && now - sampledAt <= Self.maximumAge
            && width > 0 && height > 0
            && environmentalMask.count == width * height
            && supportedFraction >= Self.minimumSupportedFraction
    }

    func removedEnvironmentFraction(for zoomRatio: Double) -> Double? {
        guard zoomRatio.isFinite, zoomRatio > 1,
              width > 0, height > 0, environmentalMask.count == width * height else { return nil }

        let halfWidth = CGFloat(1 / zoomRatio) / 2
        let halfHeight = CGFloat(1 / zoomRatio) / 2
        let minX = 0.5 - halfWidth, maxX = 0.5 + halfWidth
        let minY = 0.5 - halfHeight, maxY = 0.5 + halfHeight
        var total = 0
        var removed = 0

        for y in 0..<height {
            for x in 0..<width where environmentalMask[y * width + x] != 0 {
                total += 1
                let pointX = (CGFloat(x) + 0.5) / CGFloat(width)
                let pointY = (CGFloat(y) + 0.5) / CGFloat(height)
                if pointX < minX || pointX > maxX || pointY < minY || pointY > maxY {
                    removed += 1
                }
            }
        }

        guard total > 0 else { return 0 }
        return Double(removed) / Double(total)
    }
}

actor LiveEnvironmentAnalyzer {
    private let segmenter = DETRSegmenter()

    func analyze(_ image: CGImage, sampledAt: TimeInterval) async throws -> LiveEnvironmentSignal {
        let segmentation = try await segmenter.segment(image)
        let mapping = SegmentationTaxonomy.Mapping(labels: segmentation.labels)
        let total = segmentation.width * segmentation.height
        guard segmentation.width > 0, segmentation.height > 0,
              segmentation.classIndices.count == total else {
            throw SceneModelError.unexpectedOutput("Live environment: invalid segmentation dimensions")
        }

        var supportedClasses = [Bool](repeating: false, count: mapping.familyOfClass.count)
        var environmentalClasses = [Bool](repeating: false, count: mapping.familyOfClass.count)
        for index in mapping.familyOfClass.indices {
            let familyIndex = mapping.familyOfClass[index]
            guard mapping.families.indices.contains(familyIndex) else { continue }
            let group = mapping.families[familyIndex].group
            supportedClasses[index] = group != .other
            environmentalClasses[index] = group.isEnvironmental && group != .other
        }

        var supportedCount = 0
        var mask = [UInt8](repeating: 0, count: total)
        for index in segmentation.classIndices.indices {
            let classIndex = Int(segmentation.classIndices[index])
            guard supportedClasses.indices.contains(classIndex), supportedClasses[classIndex] else { continue }
            supportedCount += 1
            if environmentalClasses[classIndex] {
                mask[index] = 1
            }
        }

        return LiveEnvironmentSignal(
            sampledAt: sampledAt,
            width: segmentation.width,
            height: segmentation.height,
            environmentalMask: mask,
            supportedFraction: Double(supportedCount) / Double(total))
    }
}
