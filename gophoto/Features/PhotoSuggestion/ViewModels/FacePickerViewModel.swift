//
//  FacePickerViewModel.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//

import Observation
import Photos

@Observable
final class FacePickerViewModel {
    enum State: Equatable {
        case idle
        case needsAccess
        case scanning(checked: Int)
        case done
    }

    private(set) var state: State = .idle
    private(set) var groups: [FaceGroup] = []
    var threshold = FaceGrouper.defaultThreshold

    private var samples: [FaceSample] = []
    private var scanTask: Task<Void, Never>?
    private let fingerprinter: FaceFingerprinting

    init(fingerprinter: FaceFingerprinting = FaceFingerprinter()) {
        self.fingerprinter = fingerprinter
    }

    var topGroups: [FaceGroup] { Array(groups.prefix(6)) }
    var faceCount: Int { samples.count }

    func startScan() {
        scanTask?.cancel()
        scanTask = Task { await scan() }
    }

    func cancelScan() {
        scanTask?.cancel()
    }

    func regroup() async {
        groups = await Self.grouped(samples, threshold: threshold)
    }

    func clear() {
        cancelScan()
        samples = []
        groups = []
        state = .idle
    }

    private func scan() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            state = .needsAccess
            return
        }
        state = .scanning(checked: 0)
        let found = await fingerprinter.collectFaces(maxFaces: 300, maxPhotos: 1500) { [weak self] checked in
            Task { @MainActor in
                guard let self, case .scanning = self.state else { return }
                self.state = .scanning(checked: checked)
            }
        }
        guard !Task.isCancelled else {
            state = .idle
            return
        }
        samples = found
        await regroup()
        state = .done
    }

    @concurrent
    nonisolated private static func grouped(_ samples: [FaceSample], threshold: Double) async -> [FaceGroup] {
        FaceGrouper.group(samples, threshold: threshold)
    }
}
