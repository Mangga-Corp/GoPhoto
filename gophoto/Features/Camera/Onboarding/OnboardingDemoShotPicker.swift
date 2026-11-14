//
//  OnboardingDemoShotPicker.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import SwiftUI
 
struct OnboardingDemoShotPicker: View {
    enum Mode { case slide, sitting }
    let mode: Mode
 
    @State private var selectedIndex = 0
    @State private var isSitting = false
    @State private var fingerOffset: CGFloat = 0
    @State private var fingerOpacity = 0.0
    @State private var fingerScale: CGFloat = 1
 
    private static let itemWidth: CGFloat = 96
    private static let spacing: CGFloat = 4
    private static let swipeDistance: CGFloat = 56
    private static let standing: [PresetAnalysis.ShotSize] = [.full, .threeQuarter, .half]
 
    private var options: [PresetAnalysis.ShotSize] { isSitting ? [.full] : Self.standing }
    private var stride: CGFloat { Self.itemWidth + Self.spacing }
 
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: Self.spacing) {
                    ForEach(options, id: \.self) { shot in
                        item(shot)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .frame(width: geometry.size.width, alignment: .leading)
                .offset(x: (geometry.size.width - Self.itemWidth) / 2 - CGFloat(selectedIndex) * stride)
                .animation(.smooth(duration: 0.3), value: selectedIndex)
                .animation(.snappy, value: options)
 
                Image(systemName: "hand.point.up.left.fill")
                    .font(AppFont.system(size: 34))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    .scaleEffect(fingerScale)
                    .opacity(fingerOpacity)
                    .position(x: geometry.size.width / 2 + fingerOffset, y: geometry.size.height / 2 + 12)
            }
            .frame(height: 34)
            .clipped()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.25), lineWidth: 1))
        .task(id: mode) {
            switch mode {
            case .slide:   await runSlide()
            case .sitting: await runSitting()
            }
        }
        .accessibilityHidden(true)
    }
 
    private func item(_ shot: PresetAnalysis.ShotSize) -> some View {
        let current = options.indices.contains(selectedIndex) ? options[selectedIndex] : options[0]
        let isSelected = shot == current
        return Text(shot.pickerTitle)
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? GoPhotoDesign.primaryText : Color.white.opacity(0.5))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background {
                if isSelected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(GoPhotoDesign.background) }
            }
            .frame(width: Self.itemWidth)
            .animation(.smooth(duration: 0.25), value: isSelected)
    }
 
    private func pause(_ milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
 
    /// Jari menggeser card: 0 -> 1 -> 2 -> 1 -> 0, diulang terus.
    private func runSlide() async {
        isSitting = false
        selectedIndex = 0
        let targets = [1, 2, 1, 0]
        while !Task.isCancelled {
            for target in targets {
                let movesLeft = target > selectedIndex     // card geser ke kiri saat pindah ke kanan
                let startX = movesLeft ? Self.swipeDistance : -Self.swipeDistance
                fingerOffset = startX
                fingerScale = 1
                withAnimation(.easeOut(duration: 0.2)) { fingerOpacity = 1 }
                await pause(300)
                guard !Task.isCancelled else { return }
 
                withAnimation(.easeInOut(duration: 0.12)) { fingerScale = 0.88 }   // jari menekan
                await pause(140)
                guard !Task.isCancelled else { return }
 
                withAnimation(.smooth(duration: 0.55)) {                          // jari menggeser
                    fingerOffset = -startX
                    selectedIndex = target
                }
                await pause(620)
                guard !Task.isCancelled else { return }
 
                withAnimation(.easeOut(duration: 0.2)) {
                    fingerOpacity = 0
                    fingerScale = 1
                }
                await pause(800)
                guard !Task.isCancelled else { return }
            }
        }
    }
 
    /// Standing (3 card) <-> Sitting (Full body saja), diulang terus.
    private func runSitting() async {
        fingerOpacity = 0
        selectedIndex = 0
        while !Task.isCancelled {
            withAnimation(.snappy) { isSitting = false; selectedIndex = 0 }
            await pause(1800)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { isSitting = true; selectedIndex = 0 }
            await pause(2600)
        }
    }
}
 
