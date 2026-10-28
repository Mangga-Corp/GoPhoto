//
//  AnalyzingViewModel.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import Foundation

final class AnalyzingViewModel {
    var onMessage: ((String) -> Void)?
    var onFinish: (() -> Void)?

    private let messages = ["Analyzing your photos", "Finding what you like", "Getting your camera ready"]
    private let stepSeconds = 1.2
    private var task: Task<Void, Never>?
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
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            let messages = self.messages, step = self.stepSeconds
            let ticker = Task { @MainActor [weak self] in
                for message in messages.dropFirst() {
                    try? await Task.sleep(for: .seconds(step))
                    guard !Task.isCancelled else { return }
                    self?.onMessage?(message)
                }
            }
            // An edit already started the analysis: wait for it rather than running it twice.
            if let id = self.preferenceID,
               let analysis = self.preferences.runningAnalysis(for: id) ?? self.preferences.reanalyze(id: id) {
                await analysis.value
            } else {
                try? await Task.sleep(for: .seconds(step * Double(messages.count)))
            }
            ticker.cancel()
            guard !Task.isCancelled else { return }
            self.onFinish?()
        }
    }

    func cancel() { task?.cancel() }
}
