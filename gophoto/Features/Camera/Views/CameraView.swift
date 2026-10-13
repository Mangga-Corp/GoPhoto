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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch viewModel.state {
            case .idle:
                ProgressView().tint(.white)

            case .running:
                if let photo = viewModel.capturedPhoto {
                    photoReview(photo.image)
                } else {
                    liveCamera
                }

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
        .overlay(alignment: .topTrailing){
            if isLiveCamera {
                AIPreferencesButton()
                    .padding(.top, 8)
                    .padding(.trailing, 16)
            }
        }
    }

    // MARK: - Subviews
    
    private var isLiveCamera: Bool {
        if case .running = viewModel.state { return viewModel.capturedPhoto == nil }
        return false
    }
    
    private var liveCamera: some View {
        CameraPreviewView(session: viewModel.session)
            .overlay {
                GuideFramesOverlay(target: viewModel.target.rect,
                                   personOutline: viewModel.personOutline,
                                   isAligned: viewModel.isAligned)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)          // show the FULL photo (no cropping)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let degrees = viewModel.tiltDegrees {
                    TiltIndicatorView(degrees: degrees, isLevel: viewModel.isLevel)
                        .padding(.top, 12)
                }
            }
            .overlay(alignment: .bottom) {
                shutterButton.padding(.bottom, 40)
            }
            .task { await viewModel.observeTilt() }
            .task { await viewModel.observePerson() }
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isLevel) { _, isNowLevel in
                isNowLevel
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.isAligned) { _, isNowAligned in
                isNowAligned                                    //tap only when it BECOMES aligned
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

    private func photoReview(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                reviewButtons.padding(.bottom, 40)
            }
    }
    
    private var reviewButtons: some View {
        HStack(spacing: 16) {
            Button("Retake") { viewModel.retake() }
                .buttonStyle(.bordered)
                .tint(.white)

            Button {
                Task { await viewModel.savePhoto() }
            } label: {
                Group {
                    switch viewModel.saveState {
                    case .idle:   Label("Save", systemImage: "square.and.arrow.down")
                    case .saving: ProgressView()
                    case .saved:  Label("Saved", systemImage: "checkmark")
                    }
                }
                .frame(minWidth: 90)   // keeps the button from jumping in size
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .disabled(viewModel.saveState != .idle)
        .sensoryFeedback(.success, trigger: viewModel.saveState) { _, newState in
            newState == .saved
        }
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
