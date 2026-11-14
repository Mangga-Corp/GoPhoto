//
//  FaceGrouper.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//

import Vision

nonisolated struct FaceGroup: Identifiable, Sendable {
    let id: Int
    var samples: [FaceSample]

    var assetIDs: Set<String> { Set(samples.map(\.assetID)) }

    var cover: FaceSample? { samples.max { $0.faceHeightShare < $1.faceHeightShare } }
}

nonisolated enum FaceGrouper {
    static let defaultThreshold = 0.6
    static let comparedMembers = 8

    static func group(_ samples: [FaceSample], threshold: Double = defaultThreshold) -> [FaceGroup] {
        var groups: [FaceGroup] = []
        for sample in samples {
            var best: (index: Int, distance: Double)?
            for (index, group) in groups.enumerated() {
                guard let distance = closestDistance(from: sample, to: group),
                      distance < threshold,
                      distance < (best?.distance ?? .infinity) else { continue }
                best = (index, distance)
            }
            if let best {
                groups[best.index].samples.append(sample)
            } else {
                groups.append(FaceGroup(id: groups.count, samples: [sample]))
            }
        }
        return groups.sorted { ($0.assetIDs.count, -$0.id) > ($1.assetIDs.count, -$1.id) }
    }

    private static func closestDistance(from sample: FaceSample, to group: FaceGroup) -> Double? {
        group.samples.prefix(comparedMembers)
            .compactMap { try? sample.fingerprint.distance(to: $0.fingerprint) }
            .min()
    }
}
