//
//  ReplayBatch.swift
//  gophoto
//
//  appMode 2 testing: "Run all" — one video replayed once per guide × framing × shot size (× scenario),
//  each run a cold start from 0:00 at 1×, so the combinations can be compared on the same input.
//  Phased + Depth is skipped (a video has no depth). Shot sizes the preset has no photos of are skipped.
//
import Foundation

nonisolated struct ReplayBatchItem: Sendable, Equatable {
    var guide: ExperimentGuide
    var framing: FramingPolicy
    var shot: PresetAnalysis.ShotSize
    var scenario: ReplayScenario

    var label: String {
        let selection = ExperimentSelection(guide: guide, framing: framing)
        return "\(selection.label) · \(shot.shortTitle) · \(scenario == .rgbObservation ? "RGB" : "Locked")"
    }
}

nonisolated struct ReplayBatchPlan: Sendable {
    let id: String
    let items: [ReplayBatchItem]
    var index = 0
    var runIDs: [String] = []
    let skipped: [String]
    /// What to put back when the batch ends.
    let restoreSelection: ExperimentSelection
    let restoreShot: PresetAnalysis.ShotSize?
    let restoreScenario: ReplayScenario

    var current: ReplayBatchItem? { items.indices.contains(index) ? items[index] : nil }
    var csvURL: URL { ReplayLibrary.results.appending(path: "replay-batch-\(id).csv") }

    /// Guides × framings in a fixed order; the Main guides have no framing choice (one run each).
    static let combinations: [(ExperimentGuide, FramingPolicy)] = [
        (.main, .autoCrop), (.mainModified, .autoCrop), (.phased, .autoCrop), (.phased, .noCrop),
    ]
    static let shots: [PresetAnalysis.ShotSize] = [.full, .threeQuarter, .half]

    static func make(id: String, scenarios: [ReplayScenario], available: [PresetAnalysis.ShotSize],
                     restore: ExperimentSelection, restoreShot: PresetAnalysis.ShotSize?,
                     restoreScenario: ReplayScenario) -> ReplayBatchPlan {
        var items: [ReplayBatchItem] = []
        var skipped = ["Phased + Depth: this video has no depth data"]
        for shot in shots {
            guard available.contains(shot) else {
                skipped.append("\(shot.shortTitle): the preset has no photos of this shot size")
                continue
            }
            for scenario in scenarios {
                for (guide, framing) in combinations {
                    items.append(ReplayBatchItem(guide: guide, framing: framing, shot: shot, scenario: scenario))
                }
            }
        }
        return ReplayBatchPlan(id: id, items: items, skipped: skipped, restoreSelection: restore,
                               restoreShot: restoreShot, restoreScenario: restoreScenario)
    }
}
