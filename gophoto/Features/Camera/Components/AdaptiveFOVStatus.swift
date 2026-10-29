import SwiftUI

/// Small, transient status indicator for automatic adaptive-FOV zoom adjustments.
///
/// Shown only while the camera is actively changing zoom to improve framing.
/// Uses the same capsule style as the existing `InstructionPill` but smaller
/// and more subtle so it does not compete with photographer guidance.
struct AdaptiveFOVStatus: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.caption.weight(.medium))
        } icon: {
            Image(systemName: "arrow.left.and.right.magnifyingglass")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.yellow.opacity(0.75), in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adjusting framing")
    }
}

#Preview {
    VStack(spacing: 8) {
        AdaptiveFOVStatus(text: "Adjusting framing…")
        AdaptiveFOVStatus(text: "Zooming in…")
        AdaptiveFOVStatus(text: "Zooming out…")
    }
    .padding()
    .background(.gray)
}
