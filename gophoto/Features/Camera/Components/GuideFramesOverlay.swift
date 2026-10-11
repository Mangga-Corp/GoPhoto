//
//  GuideFramesOverlay.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 11/10/26.
//
//
//  GuideFramesOverlay.swift
//  gophoto
//
//  Draws the target frame and the person frame. Plain values in, no ViewModel.
//

import SwiftUI

struct GuideFramesOverlay: View {
    let target: CGRect     // normalized 0...1
    let person: CGRect?    // normalized 0...1, nil = nobody detected
    let isAligned: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Target: where you SHOULD be
                let targetRect = scaled(target, to: geo.size)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isAligned ? Color.green : Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2, dash: isAligned ? [] : [10, 6]))
                    .frame(width: targetRect.width, height: targetRect.height)
                    .position(x: targetRect.midX, y: targetRect.midY)

                // Person: where you ARE
                if let person {
                    let personRect = scaled(person, to: geo.size)
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isAligned ? Color.green : Color.red, lineWidth: 3)
                        .frame(width: personRect.width, height: personRect.height)
                        .position(x: personRect.midX, y: personRect.midY)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: person)
        .animation(.snappy, value: isAligned)
        .allowsHitTesting(false)   // never block taps on the camera
    }

    /// Normalized (0...1) → real points for this view's size.
    private func scaled(_ rect: CGRect, to size: CGSize) -> CGRect {
        CGRect(x: rect.minX * size.width,
               y: rect.minY * size.height,
               width: rect.width * size.width,
               height: rect.height * size.height)
    }
}

#Preview {
    GuideFramesOverlay(
        target: FramingTarget.ruleOfThirdsLeft.rect,
        person: CGRect(x: 0.5, y: 0.25, width: 0.3, height: 0.55),
        isAligned: false
    )
    .aspectRatio(3.0 / 4.0, contentMode: .fit)
    .background(.gray)
}
