//
//  LightingTipPill.swift
//  gophoto
//
//  Shows the light tip (sun position or backlight) under the instruction pill.
//
import SwiftUI

struct LightingTipPill: View {
    private let title: LocalizedStringKey
    private let symbol: String

    init(tip: LightTip) {
        switch tip {
        case .sun(let suggestion): self.init(suggestion: suggestion)
        case .backlight(let backlight): self.init(backlight: backlight)
        }
    }

    init(suggestion: SunSuggestion) {
        switch suggestion {
        case .swapPlaces:
            title = "Swap places so the sun is behind you."
            symbol = "arrow.left.arrow.right"
        case .findShade:
            title = "Harsh sun overhead. Find some shade."
            symbol = "sun.max.trianglebadge.exclamationmark"
        case .goldenHour:
            title = "Golden hour"
            symbol = "sun.horizon"
        }
    }

    init(backlight: BacklightTip) {
        switch backlight {
        case .swapPlaces:
            title = "Backlit. Swap places so the light is behind you."
            symbol = "arrow.left.arrow.right"
        case .moveLeft:
            title = "Backlit. Step to your left, they turn to face you."
            symbol = "arrow.turn.up.left"
        case .moveRight:
            title = "Backlit. Step to your right, they turn to face you."
            symbol = "arrow.turn.up.right"
        }
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.85), in: Capsule())
        .padding(.horizontal, 16)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 10) {
        LightingTipPill(suggestion: .swapPlaces)
        LightingTipPill(suggestion: .findShade)
        LightingTipPill(suggestion: .goldenHour)
        LightingTipPill(backlight: .swapPlaces)
        LightingTipPill(backlight: .moveLeft)
        LightingTipPill(backlight: .moveRight)
    }
    .padding()
    .background(.gray)
}
