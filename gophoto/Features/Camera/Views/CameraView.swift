//
//  CameraView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//  13 Nov (Reynard): production camera only (Phased · Auto crop). The developer camera (appMode 2:
//  debug panel, experiment picker, pose guide, replay, GT, blur toggle, ratio and grid toggles) lives
//  in the debugphoto repo (Lab). The previous version is in `_to_delete/pra-bersih-debug/`.
//

import SwiftUI
import UIKit

struct CameraView: View {
    /// The session to guide with, from the navigation that opened the camera. The camera never
    /// chooses a preference itself; its shot size is only the picker's starting point (the
    /// photographer switches shot size above the shutter). Nil = no preset.
    let sessionConfiguration: PhotoSessionConfiguration?
    /// Close (top left): ends the session; the app then returns to Preference Selection.
    /// Nil hides the button (previews).
    let onClose: (() -> Void)?
    /// The close button fires once, even if tapped again during the transition.
    @State private var isClosing = false

    init(sessionConfiguration: PhotoSessionConfiguration? = nil, onClose: (() -> Void)? = nil) {
        self.sessionConfiguration = sessionConfiguration
        self.onClose = onClose
    }

    @State private var viewModel = CameraViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingGallery = false
    @State private var isFlashing = false
    @State private var isShowingAcknowledgements = false
    @Namespace private var galleryZoom
    /// Onboarding kamera: hanya sekali, saat pertama kali install. Teksnya: Onboarding/CameraOnboardingCopy.swift
    @AppStorage("cameraOnboardingCompleted") private var cameraOnboardingCompleted = false
    @State private var onboardingFrames: [CameraOnboardingTarget: CGRect] = [:]
    private var showsCameraOnboarding: Bool { !cameraOnboardingCompleted && viewModel.state == .running }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                ProgressView().tint(.white)

            case .running:
                liveCamera
                    .overlay { cameraOnboarding }

            case .permissionDenied:
                permissionDenied

            case .restricted:
                ContentUnavailableView("Camera Not Available",
                                       systemImage: "lock",
                                       description: Text("Camera access is restricted on this iPhone (for example by Screen Time), so GoPhoto can't use it."))
                .foregroundStyle(.white)

            case .failed(let message):
                ContentUnavailableView("Camera Unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .foregroundStyle(.white)
            }

        }
        // No live view (starting, no permission, unavailable): the top bar isn't shown, so the
        // close button is, to leave the camera from any state.
        .overlay(alignment: .topLeading) {
            if viewModel.state != .running { closeButton }
        }
        .onChange(of: sessionConfiguration, initial: true) { _, configuration in
            viewModel.apply(sessionConfiguration: configuration)
        }
        .task { await viewModel.startCamera() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await viewModel.recheckPermission() }
            }
        }
        .onDisappear { Task { await viewModel.stopCamera() } }
        // The gallery covers the camera: stop the feed (and the per-frame detection) meanwhile.
        .onChange(of: isShowingGallery) { _, showing in
            Task { if showing { await viewModel.stopCamera() } else { await viewModel.resumeCamera() } }
        }
        .alert("Something went wrong", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $isShowingAcknowledgements) {
            AcknowledgementsView()
                .preferredColorScheme(.light)
                .tint(GoPhotoDesign.primary)
        }
        .fullScreenCover(isPresented: $isShowingGallery) {
            LatestPhotoView()
                .navigationTransition(.zoom(sourceID: "gallery", in: galleryZoom))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Layout (like the Camera app: slim top bar, 4:3 image, big bottom area)

    private var liveCamera: some View {
        VStack(spacing: 0) {
            topBar

            cameraPreview
                .reportOnboardingFrame(.preview, into: $onboardingFrames)
                .layoutPriority(1)   // after the frame report: VStack only sees the outermost priority

            VStack(spacing: 10) {
                shotSizePicker
                shutterButton
                    .reportOnboardingFrame(.shutter, into: $onboardingFrames)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        GalleryShortcutButton { isShowingGallery = true }
                            .matchedTransitionSource(id: "gallery", in: galleryZoom)
                            .padding(.leading, 24)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)   // centred in the bottom area
        }
        // Motion runs 30×/s and redraws the camera screen each time: stop it while the gallery
        // covers the camera, otherwise the gallery underneath it is rebuilt 30×/s too (lag).
        .task(id: isShowingGallery) {
            guard !isShowingGallery else { return }
            await viewModel.observeTilt()
        }
        .task { await viewModel.observePerson() }
        .task { await viewModel.observeZoom() }
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isLevel) { _, isNowLevel in
            isNowLevel
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isReady) { _, isNowReady in
            isNowReady
        }
        .onChange(of: viewModel.captureCount) {
            Task {
                isFlashing = true
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.2)) { isFlashing = false }
            }
        }
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 1.0), trigger: viewModel.captureCount)
    }

    /// The live preview with every guide layer on top. Each layer is its own property so the
    /// compiler can type-check them one by one instead of one huge overlay chain.
    private var cameraPreview: some View {
        CameraPreviewView(session: viewModel.session)
            .overlay { guideVisuals }
            .overlay { CameraGridOverlay(aspect: .fourThree, showsGrid: true) }
            .overlay { HorizonLevelView(state: viewModel.horizon) }
            .overlay {
                GuidanceMotionOverlay(
                    instruction: viewModel.phasedMotion,
                    pitchError: viewModel.phasedPitchError,
                    isEnabled: !isShowingGallery && !showsCameraOnboarding
                )
            }
            .overlay(alignment: .bottom) { bottomStepCard }
            .overlay(alignment: .trailing) { sideBar }
            .overlay(alignment: .top) { instructionPill }
            .overlay { flashOverlay }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .layoutPriority(1)
    }

    // MARK: Onboarding (first install only)

    @ViewBuilder private var cameraOnboarding: some View {
        if showsCameraOnboarding {
            CameraOnboardingView(frames: onboardingFrames) {
                withAnimation(.easeOut(duration: 0.25)) { cameraOnboardingCompleted = true }
            }
            .transition(.opacity)
        }
    }

    // MARK: Preview layers

    /// Person choice (dim + tap). The Auto crop is not drawn: the green pill says ready.
    private var guideVisuals: some View {
        PhasedPreviewLayer(dimMask: viewModel.selectionDimMask,
                           isChoosing: viewModel.phasedInstruction == .tapPerson,
                           cropWindow: nil,
                           isReady: viewModel.phased.ready) { point in
            viewModel.tapPreview(at: point)
        }
    }

    /// The distance bar while the distance phase runs (green zone = enter band).
    @ViewBuilder private var bottomStepCard: some View {
        if viewModel.phased.phase == .distance, let lo = viewModel.phased.sizeEnterLow,
           let hi = viewModel.phased.sizeEnterHigh {
            let centre = (lo + hi) / 2
            DistanceBar(sizeRatio: viewModel.phased.sizeRatio.map { $0 / centre },
                        tolerance: (hi - lo) / 2 / centre,
                        isOK: viewModel.phased.sizeRatio.map { $0 >= lo && $0 <= hi } ?? false)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    /// The tilt bar while the tilt phase runs (green zone = tolerance).
    @ViewBuilder private var sideBar: some View {
        if viewModel.phased.phase == .tilt {
            GuideVerticalBar(value: viewModel.phased.tiltNeed.map { max(-1, min(1, -$0 * Self.phasedTiltZone)) },
                             zone: Self.phasedTiltZone, symbol: "scope", caption: "Tilt",
                             isOK: viewModel.phased.tiltNeed.map { abs($0) <= 1 } ?? false)
                .padding(.trailing, 12)
        }
    }

    private var instructionPill: some View {
        VStack(spacing: 6) {
            PhasedInstructionPill(instruction: viewModel.phasedInstruction)
                .animation(.snappy, value: viewModel.phasedInstruction)
            if let flash = viewModel.phasedFlash {
                // A phase just finished.
                Label(flash, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.green.opacity(0.9), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.top, 12)
        .animation(.snappy, value: viewModel.phasedFlash)
        .sensoryFeedback(.success, trigger: viewModel.phasedFlash) { _, new in new != nil }
    }

    private var flashOverlay: some View {
        Color.black
            .opacity(isFlashing ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Tilt bar: the green zone's half height (the tolerance edge is ±1 in `tiltNeed`).
    private static let phasedTiltZone = 0.25

    // MARK: Top bar, shutter, permission

    /// Reserved for future controls (flash, settings). Keeps the image where the Camera app puts it.
    private var topBar: some View {
        HStack {
            closeButton
            Spacer()
            if let zoom = viewModel.currentZoomLabel {
                Text(zoom)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .accessibilityLabel("Current camera zoom \(zoom)")
                    .padding(.trailing, 16)
            }
        }
        .frame(minHeight: 44)
    }

    @ViewBuilder private var closeButton: some View {
        if let onClose {
            Button {
                guard !isClosing else { return }
                isClosing = true
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isClosing)
            .padding(.leading, 8)
            .accessibilityLabel("Close camera")
            .accessibilityIdentifier("camera.close")
        }
    }

    /// Shot sizes like TikTok's camera modes: full body only while the person sits, the
    /// preference's shot sizes while they stand. Hidden without a preset.
    @ViewBuilder private var shotSizePicker: some View {
        let options = viewModel.shotOptions
        if let note = viewModel.phasedShotNote {
            Text(note).font(.caption2).foregroundStyle(.white.opacity(0.7))
        }
        if !options.isEmpty {
            ShotSizePicker(options: options, selection: viewModel.activeShot,
                           posture: viewModel.posture) { viewModel.selectShot($0) }
                .sensoryFeedback(.selection, trigger: viewModel.activeShot)
        }
    }

    private var shutterButton: some View {
        Button {
            Task { await viewModel.takePhoto() }
        } label: {
            ZStack {
                Circle().fill(.white).frame(width: 68, height: 68)
                Circle().stroke(.white, lineWidth: 4).frame(width: 80, height: 80)
            }
        }
        .disabled(viewModel.isCapturing)
        .opacity(viewModel.isCapturing ? 0.5 : 1)
        .accessibilityLabel("Take photo")
    }

    private var permissionDenied: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera")
        } description: {
            Text("GoPhoto needs your camera to guide photos. Tap Open Settings, then turn on Camera.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.goPhotoPrimary)
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    CameraView()
}
