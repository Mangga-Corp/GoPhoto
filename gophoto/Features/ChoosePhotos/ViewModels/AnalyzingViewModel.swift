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

    var initialMessage: String { messages[0] }

    /// Frontend-only simulation. Replace the body with the real AI call later,
    /// then call onFinish when it completes.
    func start(with photos: [PhotoItem]) {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let messages = self?.messages, let step = self?.stepSeconds else { return }
            for message in messages.dropFirst() {
                try? await Task.sleep(for: .seconds(step))
                guard !Task.isCancelled else { return }
                self?.onMessage?(message)
            }
            try? await Task.sleep(for: .seconds(step))
            guard !Task.isCancelled else { return }
            self?.onFinish?()
        }
    }

    func cancel() { task?.cancel() }
}
