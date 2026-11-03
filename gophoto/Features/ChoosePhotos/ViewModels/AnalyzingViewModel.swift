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

    private let messages = ["Analyzing your photos", "Finding what you like", "Getting your camera ready"]
    private let stepSeconds = 1.2
    private var task: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var progress = 0.0
    private let preferenceID: UUID?
    private let preferences: PreferencesViewModel

    /// - Parameter preferenceID: the preset whose photos are analysed; the result is saved
    ///   with it. Nil only in previews (messages only, nothing analysed).
    init(preferenceID: UUID? = nil, preferences: PreferencesViewModel = .shared) {
        self.preferenceID = preferenceID
        self.preferences = preferences
    }

    var initialMessage: String { messages[0] }

    /// Runs the real on-device analysis while the messages rotate, then calls onFinish.
    /// The analysis belongs to `PreferencesViewModel`, so leaving this screen does not stop it.
    func start(with photos: [PhotoItem]) {
        task?.cancel()
        progressTask?.cancel()
        progress = 0
        onProgress?(progress)
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let messages = self.messages, step = self.stepSeconds
            self.progressTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.advanceProgress(to: 0.58, over: 1.5)
                await self.advanceProgress(to: 0.80, over: 6)
                await self.advanceProgress(to: 0.90, over: 22)
            }
            let ticker = Task { @MainActor [weak self] in
                for message in messages.dropFirst() {
                    try? await Task.sleep(for: .seconds(step))
                    guard !Task.isCancelled else { return }
                    self?.onMessage?(message)
                }
            }
            var analysisSucceeded = false
            // An edit already started the analysis: wait for it rather than running it twice.
            if let id = self.preferenceID,
               let analysis = self.preferences.runningAnalysis(for: id) ?? self.preferences.reanalyze(id: id) {
                await analysis.value
                analysisSucceeded = self.preferences.session(for: id)?.phase == .completed
                    && self.preferences.preference(id: id)?.analysis?.isCurrent == true
            } else {
                try? await Task.sleep(for: .seconds(step * Double(messages.count)))
            }
            ticker.cancel()
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
