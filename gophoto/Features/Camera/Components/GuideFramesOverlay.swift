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
    let target: CGRect          // normalized 0...1
    let personOutline: CGImage? // ring image covering the whole frame; nil = nobody
    let isAligned: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                
                let targetRect = scaled(target, to: geo.size)
                // Target: where you SHOULD be (rectangle for now; silhouette later)
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isAligned ? Color.green : Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2, dash: isAligned ? [] : [10, 6]))
                    .frame(width: targetRect.width, height: targetRect.height)
                    .position(x: targetRect.midX, y: targetRect.midY)

                // Person: an outline around where you ARE
                if let personOutline {
                    (isAligned ? Color.green : Color.red)
                        .mask {
                            Image(decorative: personOutline, scale: 1)
                                .resizable()            // stretch to the full frame, like the photo
                        }
                }
            }
        }
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
        personOutline: nil,
        isAligned: false
    )
    .aspectRatio(3.0 / 4.0, contentMode: .fit)
    .background(.gray)
}
