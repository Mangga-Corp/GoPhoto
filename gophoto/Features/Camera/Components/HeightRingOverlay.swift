//
//  HeightRingOverlay.swift
//  gophoto
//
//  Mode C, camera-height step, shown from the photographer's side: the phone puck stays in
//  the middle of the screen (= where the phone is now) and a slot shows where it must go.
//  Phone too high → slot below the puck; lower the phone and the slot rises into the puck.
//  Tilting past `tiltWarn` shows a note to move the whole phone and buzzes once, since
//  people tend to tilt instead of moving.
//  Plain values in, no ViewModel.
//
import SwiftUI

struct HeightRingOverlay: View {
    /// Eyes now, normalized (origin top-left).
    let eye: CGPoint
    /// Where the eyes must be, normalized y (may be outside 0...1 when far off).
    let targetY: CGFloat
    /// Phone pitch minus the preset's (+ = tilted further down). nil = no angle target.
    let tiltError: Double?
    let isOK: Bool

    /// Tilt that counts as "tilting instead of moving" (the tilt step's own enter tolerance).
    private static let tiltWarn = GuideFlow.tiltEnter

    private var isTilting: Bool { abs(tiltError ?? 0) > Self.tiltWarn }

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

                if isTilting, !isOK {
                    Text("Don't tilt, move the whole phone")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.85), in: Capsule())
                        .position(x: x, y: y - Self.puck / 2 - 22)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 1)
        }
        .animation(.easeOut(duration: 0.12), value: eye)
        .animation(.easeOut(duration: 0.12), value: targetY)
        .animation(.easeOut(duration: 0.12), value: isOK)
        .sensoryFeedback(trigger: isTilting) { _, tilting in tilting ? .warning : nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the instruction pill says what to do
    }
}

#Preview {
    HeightRingOverlay(eye: CGPoint(x: 0.5, y: 0.6), targetY: 0.3, tiltError: 4, isOK: false)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .background(.gray)
}
