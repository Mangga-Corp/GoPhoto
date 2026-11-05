//
//  ShotSizePicker.swift
//  gophoto
//
//  The shot size row above the shutter, like the camera modes in TikTok: swipe left / right (or
//  tap) to pick; the centred option is the one in use. A seated person only gets full body, a
//  standing one the shot sizes the preference has photos of.
//

import SwiftUI

struct ShotSizePicker: View {
    let options: [PresetAnalysis.ShotSize]
    let selection: PresetAnalysis.ShotSize?
    let posture: BodyPosture?
    let onSelect: (PresetAnalysis.ShotSize) -> Void

    /// Every option has the same width, so snapping one to the leading content margin centres it.
    private static let itemWidth: CGFloat = 96
    private static let spacing: CGFloat = 4
    private static var stride: CGFloat { itemWidth + spacing }

    /// The option centred by the scroll, committed when the scroll comes to rest.
    @State private var centeredIndex = 0

    var body: some View {
        VStack(spacing: 6) {
            postureCaption
            GeometryReader { geometry in
                let margin = max(0, (geometry.size.width - Self.itemWidth) / 2)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Self.spacing) {
                            ForEach(options, id: \.self) { shot in
                                item(shot)
                                    .id(shot)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .contentMargins(.horizontal, margin, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                    .onScrollGeometryChange(for: Int.self) { geo in
                        Int(((geo.contentOffset.x + geo.contentInsets.leading) / Self.stride).rounded())
                    } action: { _, index in
                        centeredIndex = index
                    }
                    .onScrollPhaseChange { _, phase in
                        guard phase == .idle, options.indices.contains(centeredIndex) else { return }
                        let shot = options[centeredIndex]
                        if shot != selection { onSelect(shot) }
                    }
                    .onAppear { scroll(proxy, animated: false) }
                    .onChange(of: selection) { scroll(proxy, animated: true) }
                    .onChange(of: options) { scroll(proxy, animated: true) }
                }
            }
            .frame(height: 34)
        }
        .animation(.snappy, value: options)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shot size")
    }

    private func item(_ shot: PresetAnalysis.ShotSize) -> some View {
        let isSelected = shot == selection
        return Button {
            onSelect(shot)
        } label: {
            Text(shot.pickerTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.black : Color.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background {
                    if isSelected { Capsule().fill(Color.white) }
                }
                .frame(width: Self.itemWidth)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Why the row looks the way it does: a seated person only gets full body.
    @ViewBuilder private var postureCaption: some View {
        if let posture {
            Label(posture == .sitting ? "Sitting · full body only" : "Standing",
                  systemImage: posture == .sitting ? "chair.fill" : "figure.stand")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .transition(.opacity)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let selection, options.contains(selection) else { return }
        if animated {
            withAnimation(.snappy) { proxy.scrollTo(selection, anchor: .center) }
        } else {
            proxy.scrollTo(selection, anchor: .center)
        }
    }
}
