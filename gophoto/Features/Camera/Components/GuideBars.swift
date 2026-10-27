//
//  GuideBars.swift
//  gophoto
//
//  One bar per guide step (modes B and C): an icon moves along the bar and has to
//  sit in the green zone. Only the bar of the step being fixed is shown.
//  Plain values in, no ViewModel.
//
import Foundation
import SwiftUI

/// Distance: a person icon on a horizontal bar. Too close = left, too far = right,
/// so stepping back moves the icon right. Log scale, so 2x too close and 2x too far
/// sit the same distance from the centre.
struct DistanceBar: View {
    /// Live size / target size (> 1 = person too big = too close). Nil = not measured.
    let sizeRatio: Double?
    /// Size tolerance that counts as right (0.15 = ±15%).
    let tolerance: Double
    let isOK: Bool

    /// Ratio at the ends of the bar (2 = twice too big / half too small).
    private static let span = 2.0

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let zoneLeft = x(1 + tolerance, w), zoneRight = x(1 - tolerance, w)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(height: 6)
                    Capsule().fill(Color.green.opacity(0.8))
                        .frame(width: zoneRight - zoneLeft, height: 10)
                        .offset(x: zoneLeft)
                    if let sizeRatio {
                        Image(systemName: "figure.stand")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isOK ? Color.green : Color.yellow)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .position(x: x(sizeRatio, w), y: geo.size.height / 2)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 30)
            HStack {
                Text("Too close")
                Spacer()
                Text("Too far")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.15), value: sizeRatio)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// x position for a size ratio: centre = right size, left = too close, right = too far.
    private func x(_ ratio: Double, _ width: CGFloat) -> CGFloat {
        let t = -log(max(ratio, 1e-3)) / log(Self.span)          // -1 (too close) ... +1 (too far)
        let clamped = min(1, max(-1, t))
        return width * CGFloat((clamped + 1) / 2)
    }

    private var accessibilityText: String {
        guard let sizeRatio else { return "Distance not measured" }
        if isOK { return "Distance is right" }
        return sizeRatio > 1 ? "Too close" : "Too far"
    }
}

/// Camera height or tilt: an icon on a vertical bar, green zone in the middle.
struct GuideVerticalBar: View {
    /// -1 (bottom) ... +1 (top) is the full bar; nil = not measured.
    let value: Double?
    /// Half-height of the green zone, in the same units as `value`.
    let zone: Double
    let symbol: String
    let caption: String
    let isOK: Bool

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let h = geo.size.height
                ZStack(alignment: .top) {
                    Capsule().fill(Color.white.opacity(0.25)).frame(width: 6)
                    Capsule().fill(Color.green.opacity(0.8))
                        .frame(width: 10, height: CGFloat(zone) * h)
                        .offset(y: y(zone, h))
                    if let value {
                        Image(systemName: symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isOK ? Color.green : Color.yellow)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .position(x: geo.size.width / 2, y: y(value, h))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: 36, height: 180)
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeOut(duration: 0.15), value: value)
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the instruction pill says what to do
    }

    /// y position (from the top) for a value: +1 = top, 0 = middle, -1 = bottom.
    private func y(_ v: Double, _ height: CGFloat) -> CGFloat {
        let clamped = min(1, max(-1, v))
        return height * CGFloat((1 - clamped) / 2)
    }
}

#Preview {
    VStack(spacing: 24) {
        DistanceBar(sizeRatio: 1.4, tolerance: 0.15, isOK: false)
        DistanceBar(sizeRatio: 1.05, tolerance: 0.15, isOK: true)
        HStack {
            GuideVerticalBar(value: 0.5, zone: 0.2, symbol: "iphone", caption: "Height", isOK: false)
            GuideVerticalBar(value: -0.1, zone: 0.2, symbol: "scope", caption: "Tilt", isOK: true)
        }
    }
    .padding()
    .background(.gray)
}
