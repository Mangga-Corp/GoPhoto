//
//  HeightRuleCard.swift
//  gophoto
//
//  Mode E: where to hold the phone, as a body landmark ("at their chest"),
//  from the preset analysis. Not measured; the photographer taps Done.
//
import SwiftUI

struct HeightRuleCard: View {
    /// `CameraHeightLevel.rawValue`, or "chestToWaist" (PRD fixed rule).
    let rule: String
    var onDone: () -> Void

    private static let figureHeight: CGFloat = 120

    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .top) {
                Image(systemName: "figure.stand")
                    .resizable()
                    .scaledToFit()
                    .frame(height: Self.figureHeight)
                    .foregroundStyle(.white.opacity(0.85))
                marker
            }
            .frame(width: 70, height: Self.figureHeight)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Hold the phone at this height, then keep it there.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                Button("Done", action: onDone)
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .foregroundStyle(.black)
            }
        }
        .padding(14)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    /// Yellow line (or band) across the figure at the body height, measured from the top.
    @ViewBuilder
    private var marker: some View {
        let band = Self.band(for: rule)
        let isLine = band.lowerBound == band.upperBound
        let top = band.lowerBound * Self.figureHeight
        let height = isLine ? 4 : (band.upperBound - band.lowerBound) * Self.figureHeight
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.yellow.opacity(isLine ? 1 : 0.6))
            .frame(width: 70, height: height)
            .offset(y: isLine ? top - 2 : top)
    }

    private var title: String {
        switch rule {
        case "aboveHead":    "Above their head"
        case "eye":          "At their eyes"
        case "shoulder":     "At their chest"
        case "hip":          "At their waist"
        case "knee":         "At their knees"
        case "ground":       "Near the ground"
        case "chestToWaist": "Between their chest and waist"
        default:             "Phone height"
        }
    }

    /// Fraction of the figure from the top (0 = top of head, 1 = feet). Approximate body proportions.
    private static func band(for rule: String) -> ClosedRange<CGFloat> {
        switch rule {
        case "aboveHead":    0...0
        case "eye":          0.07...0.07
        case "shoulder":     0.22...0.22
        case "hip":          0.5...0.5
        case "knee":         0.72...0.72
        case "ground":       0.97...0.97
        case "chestToWaist": 0.25...0.5
        default:             0.4...0.4
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        HeightRuleCard(rule: "shoulder") {}
        HeightRuleCard(rule: "chestToWaist") {}
    }
    .padding()
    .background(.gray)
}
