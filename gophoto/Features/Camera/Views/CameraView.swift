//
//  CameraView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//
//  CameraView.swift
//  gophoto
//

import SwiftUI
import UIKit

struct CameraView: View {
    /// Which camera to build. Change this number:
    /// 1 = testing: clean camera for testers. Guide B + crop, grid on, 4:3. No pose guide,
    ///     no debug, no pickers.
    /// 2 = developer: everything (debug panel, mode picker, pose guide picker, grid, ratio).
    private static let appMode = 1
    private static var isTesting: Bool { appMode == 2 }

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
    @State private var isShowingAcknowledgements = false
    @State private var stepBanner: String?
    @Namespace private var galleryZoom
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                ProgressView().tint(.white)

            case .running:
                liveCamera

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
        }
        .sheet(isPresented: $isShowingAnalysis) {
            AnalysisResultsScreen(presetID: viewModel.presetID, presetName: viewModel.presetName ?? "Preset")
        }
        .fullScreenCover(isPresented: $isShowingGallery) {
            NavigationStack {
                GalleryView(viewModel: GalleryViewModel())
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                isShowingGallery = false
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .accessibilityLabel("Back")
                        }
                    }
            }
            .navigationTransition(.zoom(sourceID: "gallery", in: galleryZoom))
        }
    }

    // MARK: - Layout (like the Camera app: slim top bar, 4:3 image, big bottom area)

    private var liveCamera: some View {
        VStack(spacing: 0) {
            topBar

            CameraPreviewView(session: viewModel.session)
                .overlay {
                    // Step modes (B, C): rings only for left/right and the final "ready" state.
                    if viewModel.guideMode.crops {
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
                    } else if showsRing {
                        GuideRingOverlay(target: viewModel.target.rect,
                                         person: viewModel.personBox,
                                         isAligned: viewModel.isReady)      // green = ready
                    }
                }
                .overlay {
                    // Ratio mask + thirds grid, under the guide visuals.
                    CameraGridOverlay(aspect: viewModel.captureAspect, showsGrid: isDeveloper ? showsGrid : true)
                }
                .overlay {
                    HorizonLevelView(state: viewModel.horizon)
                }
                .overlay {
                    if !showsStepBar {
                        DirectionArrowOverlay(instruction: viewModel.instruction)
                    }
                }
                .overlay(alignment: .bottom) {
                    if activeStep == .heightRule, let rule = viewModel.evaluation.heightRule {
                        HeightRuleCard(rule: rule) { viewModel.confirmPhoneHeight() }
                            .padding(.bottom, 12)
                    } else if activeStep == .distance {
                        DistanceBar(sizeRatio: viewModel.barSizeRatio, tolerance: GuideFlow.sizeEnter,
                                    isOK: viewModel.evaluation.checks[.distance] == .ok)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                    }
                }
                .overlay {
                    // Mode C: camera height as two rings on the subject's eyes, not a bar.
                    if activeStep == .height, viewModel.evaluation.heightUsesRings,
                       let rings = viewModel.heightRings {
                        HeightRingOverlay(eye: rings.eye, targetY: rings.targetY,
                                          // "Don't tilt" only once the tilt is set (C); in B it comes after.
                                          tiltError: viewModel.guideMode.tiltBeforeHeight ? viewModel.pitchError : nil,
                                          isOK: viewModel.evaluation.checks[.height] == .ok)
                    }
                }
                .overlay(alignment: .top) {
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
                .overlay(alignment: .trailing) {
                    if activeStep == .height, !viewModel.evaluation.heightUsesRings {
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
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        InstructionPill(instruction: viewModel.instruction)
                        if let tip = viewModel.lighting.tip {
                            LightingTipPill(tip: tip)
                        } else if let advice = viewModel.lighting.recommendation {
                            LightingAdvicePill(recommendation: advice)
                        }
                        if showsDebug, !viewModel.guideMode.steps.isEmpty, viewModel.instruction != .findPerson {
                            GuideChecklistView(steps: viewModel.guideMode.steps, checks: viewModel.evaluation.checks)
                        }
                    }
                    .padding(.top, 12)
                }
                .overlay(alignment: .bottomTrailing) {
                    // Optional side-view pose guide (A / B), picked next to the ladybug.
                    if activePoseGuide != .off {
                        PoseGuidePanel(style: activePoseGuide, state: viewModel.poseGuide)
                            .padding(8)
                            .padding(.bottom, activeStep == .distance ? 48 : 0)   // clear of the distance bar
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showsDebug {
                        GuideDebugPanel(viewModel: viewModel) { isShowingAnalysis = true }
                            .padding(8)
                    }
                }
                .overlay {
                    Color.black
                        .opacity(isFlashing ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .layoutPriority(1)

            shutterButton
                .frame(maxWidth: .infinity, maxHeight: .infinity)   // centred in the bottom area
                .overlay(alignment: .leading){
                    GalleryShortcutButton {isShowingGallery = true}
                        .matchedTransitionSource(id: "gallery", in: galleryZoom)
                        .padding(.leading, 24)
                }
        }
        .task { await viewModel.observeTilt() }
        .task { await viewModel.observePerson() }
        .task { await viewModel.observeExposure() }
        .task { await viewModel.lighting.run() }
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

    // MARK: Step visuals (modes B and C)

    /// Degrees at the ends of the height and tilt bars.
    private static let barRange = 15.0

    private var activeStep: GuideStep? {
        viewModel.guideMode.steps.isEmpty ? nil : viewModel.evaluation.activeStep
    }

    private var showsStepBar: Bool {
        activeStep == .distance || activeStep == .height || activeStep == .tilt || activeStep == .heightRule
    }

    private var showsRing: Bool {
        viewModel.guideMode.steps.isEmpty || activeStep == .horizontal || activeStep == .vertical
            || viewModel.isReady
    }

    /// Reserved for future controls (flash, settings). Keeps the image where the Camera app puts it.
    private var topBar: some View {
        HStack {
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
            Button {
                isShowingAcknowledgements = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Acknowledgements")
            AIPreferencesButton()
                .padding(.horizontal, 16)
                .frame(height: 44)
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
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
    }
}

#Preview {
    CameraView()
}
