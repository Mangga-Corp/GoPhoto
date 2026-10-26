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
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var selected: Adjustment = .strength

    private var isChanged: Bool { baseline != nil && settings != baseline }

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Adjustment.allCases) { item in
                        Button {
                            selected = item
                        } label: {
                            Label(item.title, systemImage: item.icon)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selected == item ? Color.accentColor.opacity(0.2) : Color.clear, in: Capsule())
                                .overlay(Capsule().stroke(selected == item ? Color.accentColor : .secondary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == item ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)

            Slider(value: binding(for: selected), in: selected.range)
                .padding(.horizontal, 16)
                .disabled(baseline == nil)
                .accessibilityLabel(selected.title)

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Revert to AI") {
                    if let baseline { settings = baseline }
                }
                .disabled(!isChanged)
                Spacer()
                Button(action: onSave) {
                    if isSaving { ProgressView() } else { Text("Save").bold() }
                }
                .disabled(baseline == nil || isSaving)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .disabled(isSaving)
    }

    private func binding(for item: Adjustment) -> Binding<Float> {
        Binding(get: { settings[keyPath: item.keyPath] },
                set: { settings[keyPath: item.keyPath] = $0 })
    }
}
