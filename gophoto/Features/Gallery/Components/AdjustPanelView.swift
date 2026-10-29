//
//  AdjustPanelView.swift
//  gophoto
//
//  Manual editing under the full-screen viewer. The sliders start at what AI Enhance chose for
//  this photo (`baseline`), so the first thing on screen is the AI result; "Revert to AI" puts
//  every slider back there. Save writes a new photo to Photos and the gallery.
//

import SwiftUI

/// One slider: a parameter of `PhotoEnhancer.Settings` with the range the sliders allow.
nonisolated enum Adjustment: String, CaseIterable, Identifiable {
    case strength, brightness, contrast, saturation, vibrance, warmth, tint
    case shadows, clarity, sharpness, skin, vignette

    var id: String { rawValue }

    var title: String {
        switch self {
        case .strength:   "Intensity"
        case .brightness: "Brightness"
        case .contrast:   "Contrast"
        case .saturation: "Saturation"
        case .vibrance:   "Vibrance"
        case .warmth:     "Warmth"
        case .tint:       "Tint"
        case .shadows:    "Shadows"
        case .clarity:    "Clarity"
        case .sharpness:  "Sharpness"
        case .skin:       "Skin"
        case .vignette:   "Vignette"
        }
    }

    var icon: String {
        switch self {
        case .strength:   "wand.and.stars"
        case .brightness: "sun.max"
        case .contrast:   "circle.lefthalf.filled"
        case .saturation: "drop"
        case .vibrance:   "sparkles"
        case .warmth:     "thermometer.medium"
        case .tint:       "eyedropper"
        case .shadows:    "moon"
        case .clarity:    "triangle"
        case .sharpness:  "scope"
        case .skin:       "face.smiling"
        case .vignette:   "circle.dashed"
        }
    }

    var keyPath: WritableKeyPath<PhotoEnhancer.Settings, Float> {
        switch self {
        case .strength:   \.strength
        case .brightness: \.exposureEV
        case .contrast:   \.contrast
        case .saturation: \.saturation
        case .vibrance:   \.vibrance
        case .warmth:     \.warmthKelvin
        case .tint:       \.tint
        case .shadows:    \.shadowLift
        case .clarity:    \.clarity
        case .sharpness:  \.sharpness
        case .skin:       \.skinSmoothing
        case .vignette:   \.vignette
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .strength:   0...1
        case .brightness: -1...1
        case .contrast:   0.7...1.4
        case .saturation: 0.5...1.5
        case .vibrance:   0...1
        case .warmth:     -1000...1500
        case .tint:       -30...30
        case .shadows:    0...1
        case .clarity:    0...1
        case .sharpness:  0...1.5
        case .skin:       0...1
        case .vignette:   0...1
        }
    }
}

struct AdjustPanelView: View {
    @Binding var settings: PhotoEnhancer.Settings
    /// What AI Enhance chose for this photo; nil while it is still being measured.
    let baseline: PhotoEnhancer.Settings?

    @State private var selected: Adjustment = .strength

    private var isChanged: Bool { baseline != nil && settings != baseline }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(selected.title).font(.headline)
                Spacer()
                Button("Revert to AI") {
                    if let baseline { settings = baseline }
                }
                .font(.subheadline)
                .disabled(!isChanged)
            }
            .padding(.horizontal, 16)

            Slider(value: binding(for: selected), in: selected.range)
                .padding(.horizontal, 16)
                .disabled(baseline == nil)
                .accessibilityLabel(selected.title)

            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Adjustment.allCases) { item in
                        let isSelected = selected == item
                        Button {
                            selected = item
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear, in: Circle())
                                Text(item.title).font(.caption2)
                            }
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .frame(minWidth: 64)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func binding(for item: Adjustment) -> Binding<Float> {
        Binding(get: { settings[keyPath: item.keyPath] },
                set: { settings[keyPath: item.keyPath] = $0 })
    }
}
