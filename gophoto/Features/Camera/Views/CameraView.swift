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
    @State private var viewModel = CameraViewModel()
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var isShowingGallery = false
    @State private var isFlashing = false
    @AppStorage("showGuideDebug") private var isShowingDebug = false
    @State private var isShowingAnalysis = false
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
        .alert("Something went wrong", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                        CropPreviewOverlay(window: viewModel.evaluation.cropWindow,
                                           isReady: viewModel.isReady)
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
                .overlay(alignment: .trailing) {
                    if activeStep == .height {
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
                    InstructionPill(instruction: viewModel.instruction)
                        .padding(.top, 12)
                }
                .overlay(alignment: .top) {
                    if !viewModel.guideMode.steps.isEmpty, viewModel.instruction != .findPerson {
                        GuideChecklistView(steps: viewModel.guideMode.steps, checks: viewModel.evaluation.checks)
                            .padding(.top, 56)   // below the instruction pill
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if isShowingDebug {
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
            Spacer()
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
