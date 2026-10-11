//
//  PersonDetector.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 11/10/26.
//
//
//  PersonDetector.swift
//  gophoto
//
//  Core layer: the ONLY place that uses Apple's Vision framework.
//  Input: one camera frame. Output: where the person is.
//

import Vision
import CoreVideo

nonisolated final class PersonDetector {

    private let request: VNDetectHumanRectanglesRequest = {
        let request = VNDetectHumanRectanglesRequest()
        request.upperBodyOnly = false   // detect full bodies, not just upper bodies
        return request
    }()

    /// Returns the LARGEST person's box (normalized 0...1, origin TOP-LEFT), or nil if nobody is found.
    /// Expects an upright (portrait) frame.
    func detectPerson(in pixelBuffer: CVPixelBuffer) -> CGRect? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let largest = request.results?.max(by: {
            $0.boundingBox.width * $0.boundingBox.height <
            $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return nil
        }

        // Vision's origin is BOTTOM-left; SwiftUI's is TOP-left → flip Y
        let box = largest.boundingBox
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }
}
