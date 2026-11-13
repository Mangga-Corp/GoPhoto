//
//  CameraView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//

import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct CameraView: View {
    /// Which camera to build. Change this number:
    /// 1 = testing: clean camera for testers. Guide B crop-framing mode, grid on, 4:3. No pose guide,
    ///     no debug, no pickers.
    /// 2 = developer: everything (debug panel, mode picker, pose guide picker, grid, ratio).
    private static let appMode = 1
    private static var isTesting: Bool { appMode == 1 }

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

    @State private var viewModel = CameraViewModel(
        fixedSetup: CameraView.isTesting ? (mode: .heightFirstCrop, aspect: .fourThree) : nil)
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingGallery = false
    @State private var isFlashing = false
    @AppStorage("showGuideDebug") private var isShowingDebug = false
    @AppStorage(PoseGuideStyle.storageKey) private var poseGuideStyle: PoseGuideStyle = .off
    @AppStorage("showCameraGrid") private var showsGrid = false
    private var isDeveloper: Bool { !Self.isTesting }
    private var showsDebug: Bool { isDeveloper && isShowingDebug }
    /// Developer: the picked style. Testing: none.
    private var activePoseGuide: PoseGuideStyle { isDeveloper ? poseGuideStyle : .off }
    @State private var isShowingAnalysis = false
    @State private var isShowingShotAnalysis = false
    @State private var isShowingAcknowledgements = false
    @State private var isShowingExperimentInfo = false
    @State private var isPickingReplayFile = false
    @State private var isPickingReplayPhoto = false
    @State private var replayPhotoItem: PhotosPickerItem?
    @State private var stepBanner: String?
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
            } else {
                viewModel.replayAppInactive()
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
        .sheet(isPresented: $isShowingAnalysis) {
            AnalysisResultsScreen(presetID: viewModel.presetID, presetName: viewModel.presetName ?? "Preset")
        }
        // Replay (appMode 2 testing): a video from Files or Photos, copied into the app.
        .fileImporter(isPresented: $isPickingReplayFile,
                      allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie]) { result in
            guard case .success(let url) = result, let copied = try? ReplayLibrary.importFile(url) else { return }
            Task { await viewModel.loadReplayVideo(copied) }
        }
        .photosPicker(isPresented: $isPickingReplayPhoto, selection: $replayPhotoItem, matching: .videos)
        .onChange(of: replayPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let movie = try? await item.loadTransferable(type: ReplayMovie.self) {
                    await viewModel.loadReplayVideo(movie.url)
                }
                replayPhotoItem = nil
            }
        }
        .sheet(isPresented: $isShowingExperimentInfo) {
            ExperimentInfoSheet(selection: viewModel.experiment, depthSupport: viewModel.effectiveDepthSupport,
                                photoMegapixels: viewModel.largestPhotoMegapixels)
        }
        .sheet(isPresented: $isShowingShotAnalysis) {
            ShotAnalysisScreen(analysis: viewModel.presetAnalysis, photos: viewModel.presetPhotos,
                               presetName: viewModel.presetName ?? "Preset", initial: viewModel.activeShot)
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
                if isDeveloper {
                    ExperimentBar(selection: $viewModel.experiment, depthSupport: viewModel.effectiveDepthSupport) {
                        isShowingExperimentInfo = true
                    }
                }
                shotSizePicker
                if viewModel.isReplay {
                    replayControls
                } else {
                shutterButton
                    .reportOnboardingFrame(.shutter, into: $onboardingFrames)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        GalleryShortcutButton { isShowingGallery = true }
                            .matchedTransitionSource(id: "gallery", in: galleryZoom)
                            .padding(.leading, 24)
                    }
                    .overlay(alignment: .trailing) {
                        if isDeveloper { blurToggle.padding(.trailing, 16) }
                    }
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
        // Restarted whenever the frame source changes (camera ↔ replay video).
        .task(id: viewModel.sourceID) { await viewModel.observePerson() }
        .task(id: viewModel.sourceID) { await viewModel.observeEnvironment() }
        .task(id: viewModel.sourceID) { await viewModel.observeZoom() }
        .task(id: viewModel.sourceID) { await viewModel.observeDepth() }
        .task(id: viewModel.sourceID) { await viewModel.observeReplayPreview() }
        .task(id: viewModel.sourceID) { await viewModel.observeReplayEnd() }
        // A step just finished: tap + short banner so the change of task is obvious
        // (e.g. tilt is done, now move the phone up/down and keep the angle).
        .onChange(of: viewModel.evaluation.activeStep) { old, new in
            guard let old, old != new, viewModel.evaluation.checks[old] == .ok else { return }
            let next = new.map { " → now \($0.title.lowercased())" } ?? ""
            withAnimation(.snappy) { stepBanner = "\(old.title) ✓\(next)" }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                withAnimation(.easeOut) { stepBanner = nil }
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.evaluation.activeStep) { old, new in
            guard let old else { return false }
            return old != new && viewModel.evaluation.checks[old] == .ok
        }
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
    @ViewBuilder private var previewBase: some View {
        if viewModel.isReplay {
            // The video, letterboxed; guide visuals sit on the video's own rectangle.
            ReplayPreview(image: viewModel.replayImage, aspect: viewModel.replayInfo?.aspect ?? 0.5625) { guideVisuals }
        } else {
            CameraPreviewView(session: viewModel.session)
                .overlay { guideVisuals }
        }
    }

    private var cameraPreview: some View {
        previewBase
            .overlay { if !viewModel.isReplay { gridOverlay } }
            .overlay(alignment: .bottom) {
                if viewModel.isReplay {
                    ReplayBadges(simulation: viewModel.replayIsSimulation, maskNote: viewModel.replayMaskNote)
                }
            }
            .overlay { HorizonLevelView(state: viewModel.horizon) }
            .overlay {
                GuidanceMotionOverlay(
                    instruction: viewModel.isPhased ? viewModel.phasedMotion : viewModel.instruction,
                    pitchError: viewModel.isPhased ? viewModel.phasedPitchError : viewModel.pitchError,
                    isEnabled: !isShowingGallery && !isShowingAnalysis && !isShowingShotAnalysis && !showsCameraOnboarding
                )
            }
            .overlay(alignment: .bottom) { bottomStepCard }
            .overlay(alignment: .top) { stepBannerView }
            .overlay(alignment: .trailing) { sideBar }
            .overlay(alignment: .top) { instructionPill }
            .overlay(alignment: .top) { fovStatus }
            .overlay(alignment: .top) { checklist }
            .overlay(alignment: .bottomTrailing) { poseGuide }
            .overlay(alignment: .bottomLeading) { debugPanel }
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

    /// Step modes (B, C): rings only for left/right and the final "ready" state.
    @ViewBuilder private var guideVisuals: some View {
        if viewModel.isPhased {
            // Phased: person choice (dim + tap), and the Auto crop's final frame = the saved crop.
            PhasedPreviewLayer(dimMask: viewModel.selectionDimMask,
                               isChoosing: viewModel.phasedInstruction == .tapPerson,
                               cropWindow: nil,   // the crop is not shown: the green pill says ready
                               isReady: viewModel.phased.ready) { point in
                viewModel.tapPreview(at: point)
            }
        } else if viewModel.guideMode.crops {
            if showsDebug {
                // Debug: the crop window itself (outside dimmed, green when ready).
                CropPreviewOverlay(window: viewModel.evaluation.cropWindow,
                                   isReady: viewModel.isReady)
            }
            // Otherwise no frame at all: the crop is not shown to the photographer.
        } else if viewModel.guideMode == .currentOldLook {
            GuideFramesOverlay(target: viewModel.target.rect,
                               personOutline: viewModel.personOutline,
                               isAligned: viewModel.isReady)
        }
    }

    /// Ratio mask + thirds grid, under the guide visuals.
    private var gridOverlay: some View {
        // Phased shows the whole 4:3 output (no ratio crop: No crop must not crop by ratio).
        CameraGridOverlay(aspect: viewModel.isPhased ? .fourThree : viewModel.captureAspect,
                          showsGrid: isDeveloper ? showsGrid : true)
    }

    @ViewBuilder private var bottomStepCard: some View {
        if viewModel.isPhased {
            // Phased: the same distance bar while the distance phase runs (green zone = enter band).
            if viewModel.phased.phase == .distance, let lo = viewModel.phased.sizeEnterLow,
               let hi = viewModel.phased.sizeEnterHigh {
                let centre = (lo + hi) / 2
                DistanceBar(sizeRatio: viewModel.phased.sizeRatio.map { $0 / centre },
                            tolerance: (hi - lo) / 2 / centre,
                            isOK: viewModel.phased.sizeRatio.map { $0 >= lo && $0 <= hi } ?? false)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        } else if activeStep == .heightRule, let rule = viewModel.evaluation.heightRule {
            HeightRuleCard(rule: rule) { viewModel.confirmPhoneHeight() }
                .padding(.bottom, 12)
        } else if activeStep == .distance {
            DistanceBar(sizeRatio: viewModel.barSizeRatio, tolerance: GuideFlow.sizeEnter,
                        isOK: viewModel.evaluation.checks[.distance] == .ok)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder private var stepBannerView: some View {
        if let banner = stepBanner {
            Text(banner)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.green, in: Capsule())
                .padding(.top, 96)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder private var sideBar: some View {
        if viewModel.isReplay {
            EmptyView()     // height / tilt bars need sensors a video does not have
        } else if viewModel.isPhased {
            // Phased: the same tilt bar while the tilt phase runs (green zone = tolerance).
            if viewModel.phased.phase == .tilt {
                GuideVerticalBar(value: viewModel.phased.tiltNeed.map { max(-1, min(1, -$0 * Self.phasedTiltZone)) },
                                 zone: Self.phasedTiltZone, symbol: "scope", caption: "Tilt",
                                 isOK: viewModel.phased.tiltNeed.map { abs($0) <= 1 } ?? false)
                    .padding(.trailing, 12)
            }
        } else if activeStep == .height, !viewModel.evaluation.heightUsesRings {
            // Phone icon above the zone = camera too high.
            GuideVerticalBar(value: viewModel.barHeightError.map { $0 / Self.barRange },
                             zone: GuideFlow.heightEnter / Self.barRange,
                             symbol: "iphone", caption: "Height",
                             isOK: viewModel.evaluation.checks[.height] == .ok)
                .padding(.trailing, 12)
        } else if activeStep == .tilt {
            // Aim point below the zone = phone tilted down too much.
            GuideVerticalBar(value: viewModel.barTiltError.map { -$0 / Self.barRange },
                             zone: GuideFlow.tiltEnter / Self.barRange,
                             symbol: "scope", caption: "Tilt",
                             isOK: viewModel.evaluation.checks[.tilt] == .ok)
                .padding(.trailing, 12)
        }
    }

    @ViewBuilder private var instructionPill: some View {
        if viewModel.isPhased {
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
        } else {
            InstructionPill(instruction: viewModel.instruction)
                .padding(.top, 12)
        }
    }

    @ViewBuilder private var fovStatus: some View {
        if let status = viewModel.adaptiveFOVStatusText {
            AdaptiveFOVStatus(text: status)
                .padding(.top, 48)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }

    @ViewBuilder private var checklist: some View {
        if showsDebug, !viewModel.guideMode.steps.isEmpty, viewModel.instruction != .findPerson {
            GuideChecklistView(steps: viewModel.guideMode.steps, checks: viewModel.evaluation.checks)
                .padding(.top, 56)   // below the instruction pill
        }
    }

    /// Optional side-view pose guide (A / B), picked next to the ladybug.
    @ViewBuilder private var poseGuide: some View {
        if activePoseGuide != .off {
            PoseGuidePanel(style: activePoseGuide, state: viewModel.poseGuide)
                .padding(8)
                .padding(.bottom, activeStep == .distance ? 48 : 0)   // clear of the distance bar
        }
    }

    @ViewBuilder private var debugPanel: some View {
        if showsDebug {
            GuideDebugPanel(viewModel: viewModel,
                            onShowDetails: { isShowingAnalysis = true },
                            onShowShots: { isShowingShotAnalysis = true })
                .padding(8)
        }
    }

    private var flashOverlay: some View {
        Color.black
            .opacity(isFlashing ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: Step visuals (modes B and C)

    /// Degrees at the ends of the height and tilt bars.
    private static let barRange = 15.0
    /// Phased tilt bar: the green zone's half height (the tolerance edge is ±1 in `tiltNeed`).
    private static let phasedTiltZone = 0.25

    private var activeStep: GuideStep? {
        viewModel.guideMode.steps.isEmpty ? nil : viewModel.evaluation.activeStep
    }

    private var showsStepBar: Bool {
        activeStep == .distance || activeStep == .height || activeStep == .tilt || activeStep == .heightRule
    }

    // MARK: Top bar, shutter, permission

    /// Reserved for future controls (flash, settings). Keeps the image where the Camera app puts it.
    private var topBar: some View {
        HStack {
            closeButton
            if isDeveloper {
                Button {
                    isShowingDebug.toggle()
                } label: {
                    Image(systemName: isShowingDebug ? "ladybug.fill" : "ladybug")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isShowingDebug ? .yellow : .white)
                        .frame(width: 44, height: 44)
                }
                .padding(.leading, 8)
                .accessibilityLabel(isShowingDebug ? "Hide guide debug values" : "Show guide debug values")
                Menu {
                    Picker("Pose guide", selection: $poseGuideStyle) {
                        ForEach(PoseGuideStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    Image(systemName: poseGuideStyle == .off ? "figure.stand" : "figure.stand.line.dotted.figure.stand")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(poseGuideStyle == .off ? .white : .yellow)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Pose guide: \(poseGuideStyle.title)")
                Button {
                    showsGrid.toggle()
                } label: {
                    Image(systemName: showsGrid ? "grid.circle.fill" : "grid")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(showsGrid ? .yellow : .white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showsGrid ? "Hide grid" : "Show grid")
                Button {
                    Task { viewModel.isReplay ? await viewModel.exitReplay() : await viewModel.enterReplay() }
                } label: {
                    Image(systemName: viewModel.isReplay ? "film.fill" : "film")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(viewModel.isReplay ? .yellow : .white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(viewModel.isReplay ? "Source: replay video. Back to live camera" : "Source: live camera. Switch to replay video")
                Button {
                    viewModel.captureAspect = viewModel.captureAspect.next
                } label: {
                    Text(viewModel.captureAspect.title)
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(viewModel.captureAspect == .fourThree ? .white : .yellow)
                        .padding(.horizontal, 8).frame(height: 28)
                        .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Photo ratio \(viewModel.captureAspect.title)")
            }
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

    /// Developer mode only (temporary): background blur Off / On for the next photos.
    private var blurToggle: some View {
        VStack(spacing: 4) {
            Text(viewModel.bokehEnabled ? (viewModel.bokehUsesDepth ? "Blur · Apple" : "Blur · custom") : "Blur")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            HStack(spacing: 0) {
                blurOption("Off", on: false)
                blurOption("On", on: true)
            }
            .background(Color.black.opacity(0.35), in: Capsule())
        }
    }

    private func blurOption(_ title: String, on: Bool) -> some View {
        let selected = viewModel.bokehEnabled == on
        return Button {
            viewModel.bokehEnabled = on
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? .black : .white)
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background(selected ? Color.yellow : Color.clear, in: Capsule())
        }
        .accessibilityLabel("Background blur \(title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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

    /// Replay: video, play / pause / restart, "Save test frame", scenario, export, back to live.
    private var replayControls: some View {
        ReplayControls(info: viewModel.replayInfo, time: viewModel.replayTime,
                       playing: viewModel.replayPlaying, ended: viewModel.replayEnded,
                       scenario: viewModel.replayScenario, exports: viewModel.replayExports,
                       message: viewModel.replayMessage,
                       batchStatus: viewModel.replayBatchStatus,
                       onPickFiles: { isPickingReplayFile = true },
                       onPickPhotos: { isPickingReplayPhoto = true },
                       onPlayPause: { viewModel.replayPlayPause() },
                       onRestart: { viewModel.restartReplay(reason: "restart") },
                       onSaveFrame: { viewModel.saveTestFrame() },
                       onEndRun: { viewModel.finishReplayRun() },
                       onScenario: { viewModel.replayScenario = $0 },
                       onLive: { Task { await viewModel.exitReplay() } },
                       onRunAll: { viewModel.startReplayBatch(scenarios: $0) },
                       onStopBatch: { viewModel.cancelReplayBatch("stopped by you") })
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
