import SwiftUI

/// Progress of the step-by-step guide (modes B and C): which steps are done.
struct GuideChecklistView: View {
    let steps: [GuideStep]
    let checks: [GuideStep: GuideCheck]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps, id: \.self) { step in
                chip(step, checks[step])
            }
        }
        .padding(6)
        .background(.black.opacity(0.45), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chip(_ step: GuideStep, _ check: GuideCheck?) -> some View {
        let isOK = check == .ok
        let isLocked = check == .locked
        let isSkipped: Bool = { if case .skipped = check { return true } else { return false } }()
        let symbol = isOK ? "checkmark.circle.fill" : isSkipped ? "minus.circle" : isLocked ? "circle.dotted" : "circle"
        let color: Color = isOK ? .green : (isSkipped || isLocked) ? .white.opacity(0.4) : .white
        let state = isOK ? "done" : isSkipped ? "skipped" : isLocked ? "waiting" : "now"
        Label(step.title, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel("\(step.title): \(state)")
    }
}
