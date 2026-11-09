//
//  PhasedOverlays.swift
//  gophoto
//
//  Phased guide UI (appMode 2): the single instruction, the person choice (non-persons dimmed, tap
//  a person; no outline after), and the Auto crop's final frame. No per-phase ticks.
//
import SwiftUI

struct PhasedInstructionPill: View {
    let instruction: PhasedInstruction?

    var body: some View {
        if let instruction {
            Label(instruction.text, systemImage: instruction.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(instruction == .takePhoto || instruction == .holdIt
                            ? Color.green.opacity(0.85) : Color.black.opacity(0.6),
                            in: Capsule())
                .accessibilityElement(children: .combine)
                .transition(.opacity)
        }
    }
}

/// Dimming while choosing + the tap target, and the Auto crop frame once the crop is final.
struct PhasedPreviewLayer: View {
    let dimMask: CGImage?
    let isChoosing: Bool
    let cropWindow: CGRect?
    let isReady: Bool
    var onTap: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isChoosing, let dimMask {
                    Image(decorative: dimMask, scale: 1)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if let cropWindow {
                    CropPreviewOverlay(window: cropWindow, isReady: isReady)
                        .allowsHitTesting(false)
                }
                if isChoosing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            guard geo.size.width > 0, geo.size.height > 0 else { return }
                            onTap(CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height))
                        }
                        .accessibilityLabel("Tap the person to photograph")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isChoosing)
    }
}
