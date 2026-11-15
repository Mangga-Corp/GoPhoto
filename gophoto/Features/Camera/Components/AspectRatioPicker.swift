//
//  AspectRatioPicker.swift
//  gophoto
//
//  The camera's photo ratio (3:4 / 9:16): a small segmented capsule in the top bar, styled like
//  the shot-size picker (white capsule = selected) but smaller, so it never competes with the
//  shutter.
//

import SwiftUI

struct AspectRatioPicker: View {
    let selection: CameraAspectRatio
    var onSelect: (CameraAspectRatio) -> Void

    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CameraAspectRatio.allCases) { ratio in
                let isSelected = ratio == selection
                Button {
                    onSelect(ratio)
                } label: {
                    Text(ratio.title)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                        .frame(minWidth: 40, minHeight: 26)
                        .padding(.horizontal, 4)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.white)
                                    .matchedGeometryEffect(id: "ratioHighlight", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo ratio \(ratio.accessibilityName)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.black.opacity(0.35), in: Capsule())
        .animation(.snappy, value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photo ratio")
    }
}
