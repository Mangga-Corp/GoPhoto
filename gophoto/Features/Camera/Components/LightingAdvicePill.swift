//
//  LightingAdvicePill.swift
//  gophoto
//
//  Shows the weather-based lighting idea under the instruction pill.
//
import SwiftUI

struct LightingAdvicePill: View {
    let recommendation: LightingRecommendation

    var body: some View {
        Label {
            Text("\(recommendation.rule.title): \(recommendation.ideas.first?.text ?? "")")
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6), in: Capsule())
        .padding(.horizontal, 16)
        .transition(.opacity)
        .animation(.snappy, value: recommendation)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch recommendation.scene {
        case .sunny:      "sun.max"
        case .overcast:   "cloud"
        case .rainy:      "cloud.rain"
        case .misty:      "cloud.fog"
        case .heavyRain:  "cloud.heavyrain"
        case .goldenHour: "sun.horizon"
        case .night:      "light.max"
        case .unknown:    "sun.min"
        }
    }
}
