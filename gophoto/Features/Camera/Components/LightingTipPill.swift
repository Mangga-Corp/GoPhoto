//
//  LightingTipPill.swift
//  gophoto
//
//  Shows the lighting tip (sun position) under the instruction pill.
//
import SwiftUI

struct LightingTipPill: View {
    let suggestion: SunSuggestion

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.85), in: Capsule())
        .transition(.opacity)
        .animation(.snappy, value: suggestion)
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringKey {
        switch suggestion {
        case .swapPlaces: "Swap places so the sun is behind you."
        case .findShade:  "Harsh sun overhead. Find some shade."
        case .goldenHour: "Golden hour"
        }
    }

    private var symbol: String {
        switch suggestion {
        case .swapPlaces: "arrow.left.arrow.right"
        case .findShade:  "sun.max.trianglebadge.exclamationmark"
        case .goldenHour: "sun.horizon"
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        LightingTipPill(suggestion: .swapPlaces)
        LightingTipPill(suggestion: .findShade)
        LightingTipPill(suggestion: .goldenHour)
    }
    .padding()
    .background(.gray)
}
