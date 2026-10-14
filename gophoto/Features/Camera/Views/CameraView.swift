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
    
    @State private var isShowingGallery = false
    @State private var isFlashing = false
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

            case .failed(let message):
                ContentUnavailableView("Camera Unavailable",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text(message))
                    .foregroundStyle(.white)
            }
        }
        .task { await viewModel.startCamera() }
        .onDisappear { Task { await viewModel.stopCamera() } }
        .alert("Something went wrong", isPresented: $viewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
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
                    GuideFramesOverlay(target: viewModel.target.rect,
                                       personOutline: viewModel.personOutline,
                                       isAligned: viewModel.isReady)          // green = ready
                }
                .overlay {
                    HorizonLevelView(state: viewModel.horizon)
                }
                .overlay {
                    DirectionArrowOverlay(instruction: viewModel.instruction)
                }
                .overlay(alignment: .top) {
                    InstructionPill(instruction: viewModel.instruction)
                        .padding(.top, 12)
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

    /// Reserved for future controls (flash, settings). Keeps the image where the Camera app puts it.
    private var topBar: some View {
        HStack {
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
            Text("GoPhoto needs your camera to guide photos. Turn it on in Settings.")
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
