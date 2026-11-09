//
//  AnalyzingViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import Foundation

final class AnalyzingViewModel {
    var onMessage: ((String) -> Void)?
    var onProgress: ((Double) -> Void)?
    var onFinish: (() -> Void)?
    /// Called when a photo finishes analysis. `(finishedIndex, totalCount)`
    var onPhotoFinished: ((Int, Int) -> Void)?
    /// Called with the current checking description and estimated remaining seconds.
    var onCheckingUpdate: ((String, Int) -> Void)?

    private let checkingSteps = [
        "Checking your angles",
        "Analyzing your pose",
        "Reading lighting conditions",
        "Detecting face features",
        "Evaluating composition",
        "Finding your style"
    ]
    private let stepSeconds = 1.2
    private var task: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var checkingTask: Task<Void, Never>?
    private var progress = 0.0
    private let preferenceID: UUID?
    private let preferences: PreferencesViewModel
    private(set) var finishedPhotoCount = 0

    /// - Parameter preferenceID: the preset whose photos are analysed; the result is saved
    ///   with it. Nil only in previews (messages only, nothing analysed).
    init(preferenceID: UUID? = nil, preferences: PreferencesViewModel = .shared) {
        self.preferenceID = preferenceID
        self.preferences = preferences
    }

    var initialMessage: String { checkingSteps[0] }

    /// Runs the real on-device analysis while the messages rotate, then calls onFinish.
    /// The analysis belongs to `PreferencesViewModel`, so leaving this screen does not stop it.
    func start(with photos: [PhotoItem]) {
        task?.cancel()
        progressTask?.cancel()
        checkingTask?.cancel()
        progress = 0
        finishedPhotoCount = 0
        onProgress?(progress)
        onPhotoFinished?(0, photos.count)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let totalPhotos = photos.count

            // Estimate: ~3 seconds per photo
            let estimatedTotalSeconds = max(totalPhotos * 3, 10)

            // Start the checking-step ticker
            self.checkingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                var stepIndex = 0
                while !Task.isCancelled {
                    let currentStep = self.checkingSteps[stepIndex % self.checkingSteps.count]
                    let remaining = max(estimatedTotalSeconds - Int(Double(estimatedTotalSeconds) * self.progress), 1)
                    self.onCheckingUpdate?(currentStep, remaining)
                    self.onMessage?(currentStep)
                    try? await Task.sleep(for: .seconds(2.0))
                    stepIndex += 1
                }
            }

            self.progressTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.advanceProgress(to: 0.58, over: 1.5)
                await self.advanceProgress(to: 0.80, over: 6)
                await self.advanceProgress(to: 0.90, over: 22)
            }

            var analysisSucceeded = false
            if let id = self.preferenceID,
               let analysis = self.preferences.runningAnalysis(for: id) ?? self.preferences.reanalyze(id: id) {

                // Monitor per-photo progress from the session
                let monitorTask = Task { @MainActor [weak self] in
                    guard let self, let id = self.preferenceID,
                          let session = self.preferences.session(for: id) else { return }
                    var lastFinished = 0
                    while !Task.isCancelled {
                        let finished = session.finishedCount
                        let total = max(session.totalCount, totalPhotos)
                        if finished != lastFinished {
                            lastFinished = finished
                            self.finishedPhotoCount = finished
                            self.onPhotoFinished?(finished, total)
                        }
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                }

                await analysis.value
                monitorTask.cancel()

                // Final photo count update
                if let session = self.preferences.session(for: id) {
                    self.finishedPhotoCount = session.finishedCount
                    self.onPhotoFinished?(session.finishedCount, session.totalCount)
                }

                analysisSucceeded = self.preferences.session(for: id)?.phase == .completed
                    && self.preferences.preference(id: id)?.analysis?.isCurrent == true
            } else {
                // Simulate per-photo progress for preview / no-ID mode
                for i in 1...totalPhotos {
                    try? await Task.sleep(for: .seconds(self.stepSeconds))
                    guard !Task.isCancelled else { return }
                    self.finishedPhotoCount = i
                    self.onPhotoFinished?(i, totalPhotos)
                }
            }

            self.checkingTask?.cancel()
            guard !Task.isCancelled else { return }
            self.progressTask?.cancel()
            if analysisSucceeded {
                await self.advanceProgress(to: 1, over: 0.45)
                guard !Task.isCancelled else { return }
            }
            self.onFinish?()
        }
    }

    func cancel() {
        task?.cancel()
        progressTask?.cancel()
        checkingTask?.cancel()
    }

    @MainActor
    private func advanceProgress(to target: Double, over duration: TimeInterval) async {
        let start = progress
        let startTime = Date.timeIntervalSinceReferenceDate

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            let elapsed = Date.timeIntervalSinceReferenceDate - startTime
            let fraction = min(elapsed / duration, 1)
            let eased = 1 - pow(1 - fraction, 3)
            progress = start + (target - start) * eased
            onProgress?(progress)

            if fraction >= 1 { return }
        }
    }
}
