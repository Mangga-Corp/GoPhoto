//
//  GuideRingOverlay.swift
//  gophoto
//
//  Two rings instead of a frame and a body highlight: a dashed ring where the
//  person SHOULD be (size = how big), a solid ring where they ARE. Line them up.
//  Plain values in, no ViewModel.
//
import SwiftUI

struct GuideRingOverlay: View {
    let target: CGRect      // normalized person box the preset asks for
    let person: CGRect?     // normalized live person box; nil = nobody
    let isAligned: Bool

    /// Ring diameter as a fraction of the person box height, so the size difference reads at a glance.
    private static let ringScale: CGFloat = 0.45
    private static let minDiameter: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let goal = ring(for: target, in: geo.size)
            ZStack {
                Circle()
                    .stroke(isAligned ? Color.green : Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, dash: isAligned ? [] : [8, 6]))
                    .frame(width: goal.diameter, height: goal.diameter)
                    .position(goal.center)

                if let person, !isAligned {
                    let now = ring(for: person, in: geo.size)
                    Circle()
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: now.diameter, height: now.diameter)
                        .position(now.center)
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 8, height: 8)
                        .position(now.center)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 1)
        }
        .animation(.snappy, value: isAligned)
        .animation(.easeOut(duration: 0.15), value: person)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the instruction pill already says it
    }

    private func ring(for box: CGRect, in size: CGSize) -> (center: CGPoint, diameter: CGFloat) {
        let center = CGPoint(x: box.midX * size.width, y: box.midY * size.height)
        return (center, max(Self.minDiameter, box.height * size.height * Self.ringScale))
    }
}

#Preview {
    GuideRingOverlay(
        target: FramingTarget.ruleOfThirdsLeft.rect,
        person: CGRect(x: 0.4, y: 0.3, width: 0.2, height: 0.45),
        isAligned: false
    )
    .aspectRatio(3.0 / 4.0, contentMode: .fit)
    .background(.gray)
}
