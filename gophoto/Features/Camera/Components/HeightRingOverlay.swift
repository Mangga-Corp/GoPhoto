//
//  HeightRingOverlay.swift
//  gophoto
//
//  Mode C, camera-height step, shown from the photographer's side: the phone puck stays in
//  the middle of the screen (= where the phone is now) and a slot shows where it must go.
//  Phone too high → slot below the puck; lower the phone and the slot rises into the puck.
//  Plain values in, no ViewModel.
//
import SwiftUI

struct HeightRingOverlay: View {
    /// Eyes now, normalized (origin top-left).
    let eye: CGPoint
    /// Where the eyes must be, normalized y (may be outside 0...1 when far off).
    let targetY: CGFloat
    let isOK: Bool

    private static let puck: CGFloat = 54
    private static let slot = CGSize(width: 76, height: 66)

    /// Slot position, normalized. Lowering the phone (same angle) lifts the eyes in the frame,
    /// so the slot sits as far below the middle as the phone is too high.
    private var slotPosition: CGFloat { min(max(0.5 + eye.y - targetY, 0.1), 0.9) }

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width / 2
            let y = geo.size.height / 2              // the phone, now
            let slotY = slotPosition * geo.size.height
            let gap = slotY - y                      // > 0: slot below, move the phone down
            let tint: Color = isOK ? .green : .yellow
            ZStack {
                // Slot: where the phone should end up.
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isOK ? Color.green : Color.white,
                            style: StrokeStyle(lineWidth: 3, dash: isOK ? [] : [8, 6]))
                    .frame(width: Self.slot.width, height: Self.slot.height)
                    .position(x: x, y: slotY)

                // Arrows: which way to move the phone.
                if !isOK, abs(gap) > Self.puck {
                    Image(systemName: gap > 0 ? "chevron.compact.down" : "chevron.compact.up")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                        .position(x: x, y: y + gap / 2)
                }

                // Puck: the phone, always in the middle.
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .overlay(Circle().stroke(tint, lineWidth: 3))
                    .overlay(Image(systemName: isOK ? "checkmark" : "iphone")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tint))
                    .frame(width: Self.puck, height: Self.puck)
                    .position(x: x, y: y)
            }
            .shadow(color: .black.opacity(0.5), radius: 1)
        }
        .animation(.easeOut(duration: 0.12), value: eye)
        .animation(.easeOut(duration: 0.12), value: targetY)
        .animation(.easeOut(duration: 0.12), value: isOK)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the instruction pill says what to do
    }
}

#Preview {
    HeightRingOverlay(eye: CGPoint(x: 0.5, y: 0.6), targetY: 0.3, isOK: false)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .background(.gray)
}
