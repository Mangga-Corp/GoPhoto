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
    /// Frame units (origin top-left), like the tap point and the dim mask.
    let cropWindow: CGRect?
    let isReady: Bool
    /// The preview's ratio: the box shows its band of the camera frame (3:4 = the whole frame).
    var aspectRatio: CameraAspectRatio = .threeFour
    /// Point in frame units (origin top-left).
    var onTap: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geo in
            // The whole camera frame in box coordinates (larger than the box for 9:16).
            let frame = aspectRatio.previewRect(fromFrame: CGRect(x: 0, y: 0, width: 1, height: 1))
            ZStack {
                if isChoosing, let dimMask {
                    // The mask covers the whole frame: placed like the video under aspect fill.
                    Image(decorative: dimMask, scale: 1)
                        .resizable()
                        .frame(width: frame.width * geo.size.width, height: frame.height * geo.size.height)
                        .position(x: frame.midX * geo.size.width, y: frame.midY * geo.size.height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if let cropWindow {
                    CropPreviewOverlay(window: aspectRatio.previewRect(fromFrame: cropWindow), isReady: isReady)
                        .allowsHitTesting(false)
                }
                if isChoosing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { location in
                            guard geo.size.width > 0, geo.size.height > 0 else { return }
                            let inBox = CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height)
                            onTap(aspectRatio.framePoint(fromPreview: inBox))
                        }
                        .accessibilityLabel("Tap the person to photograph")
                        .accessibilityAddTraits(.isButton)
                }
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.2), value: isChoosing)
    }
}
