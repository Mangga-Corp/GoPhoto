//
//  Cameraonboardingview.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import SwiftUI
 
struct CameraOnboardingView: View {
    /// Frame tombol-tombol asli (koordinat global), dilaporkan oleh CameraView.
    let frames: [CameraOnboardingTarget: CGRect]
    let onFinish: () -> Void
 
    @State private var step: CameraOnboardingStep = .shotCards
 
    private static let pickerHeight: CGFloat = 72
    /// Jarak card putih ke demo card shot size (ubah angka ini kalau mau lebih dekat / jauh).
    private static let cardGapToPicker: CGFloat = 4
    private static let lastStep = CameraOnboardingStep.allCases.last!
 
    var body: some View {
        ZStack {
            dimLayer
 
            GeometryReader { proxy in
                let origin = proxy.frame(in: .global).origin
                ZStack {
                    visual(origin: origin)
 
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        card
                        // Step card shot size: card duduk tepat di atas demo card (dekat dengan yang dijelaskan).
                        // Step lain: card di paling bawah.
                        if step.cardAbovePicker, let shutter = local(.shutter, origin) {
                            let pickerTop = shutter.minY - 6 - Self.pickerHeight
                            Color.clear.frame(height: max(0, proxy.size.height - pickerTop + Self.cardGapToPicker))
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .accessibilityAddTraits(.isModal)
    }
 
    // MARK: Dim
 
    /// Layar digelapkan. Juga menahan semua sentuhan ke kamera.
    private var dimLayer: some View {
        Color.black.opacity(step.dimOpacity)
            .animation(.smooth(duration: 0.35), value: step)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {}
    }
 
    private func local(_ target: CameraOnboardingTarget, _ origin: CGPoint) -> CGRect? {
        frames[target]?.offsetBy(dx: -origin.x, dy: -origin.y)
    }
 
    // MARK: Visual per step
 
    @ViewBuilder
    private func visual(origin: CGPoint) -> some View {
        switch step {
        case .shotCards, .sitting:
            if let shutter = local(.shutter, origin), let preview = local(.preview, origin) {
                OnboardingDemoShotPicker(mode: step == .sitting ? .sitting : .slide)
                    .id(step)
                    .frame(width: preview.width - 24, height: Self.pickerHeight)
                    .position(x: preview.midX, y: shutter.minY - 6 - Self.pickerHeight / 2)
            }
 
        case .tiltDown, .tiltUp, .heightUp, .heightDown:
            if let preview = local(.preview, origin) {
                OnboardingMotionDemo(kind: step.motionKind, direction: step.motionDirection)
                    .id(step)
                    .frame(width: preview.width, height: preview.height)
                    .position(x: preview.midX, y: preview.midY)
            }
        }
    }
 
    // MARK: Card (gaya sama dengan WelcomeOnboardingView)
 
    private var card: some View {
        VStack(spacing: 0) {
            pageDots
                .padding(.bottom, 16)
 
            Text(step.title)
                .font(GoPhotoDesign.pageTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
 
            Text(step.message)
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
 
            Button(step == Self.lastStep ? CameraOnboardingCopy.finishButton : CameraOnboardingCopy.continueButton,
                   action: advance)
            .buttonStyle(.goPhotoPrimary)
            .padding(.top, 22)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(GoPhotoDesign.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .id(step)
        .transition(.opacity)
    }
 
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(CameraOnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == step ? GoPhotoDesign.primary : GoPhotoDesign.primaryBorder)
                    .frame(width: item == step ? 20 : 6, height: 6)
            }
        }
        .animation(.smooth(duration: 0.25), value: step)
        .accessibilityHidden(true)
    }
 
    private func advance() {
        if let next = CameraOnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.smooth(duration: 0.35)) { step = next }
        } else {
            onFinish()
        }
    }
}
 
// MARK: - Layout per step
 
extension CameraOnboardingStep {
    /// Card putih diletakkan tepat di atas demo card shot size (bukan di paling bawah).
    var cardAbovePicker: Bool {
        switch self {
        case .shotCards, .sitting: true
        default:                   false
        }
    }
 
    /// Step animasi memakai redup yang sama dengan GuidanceMotionOverlay.
    var dimOpacity: Double {
        switch self {
        case .tiltDown, .tiltUp, .heightUp, .heightDown: GuidanceAnimationStyle.dimOpacity
        default:                                         0.78
        }
    }
}
 
extension CameraOnboardingStep {
    /// Jenis dan arah animasi untuk step tilt / height.
    var motionKind: OnboardingMotionDemo.Kind {
        switch self {
        case .heightUp, .heightDown: .height
        default:                     .tilt
        }
    }
 
    var motionDirection: Direction {
        switch self {
        case .tiltDown, .heightDown: .down
        default:                     .up
        }
    }
}
