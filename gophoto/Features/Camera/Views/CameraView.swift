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
                if let image = viewModel.capturedImage {
                    photoReview(image)
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
    }

    // MARK: - Subviews

    private var liveCamera: some View {
        CameraPreviewView(session: viewModel.session)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if let degrees = viewModel.tiltDegrees {
                    TiltIndicatorView(degrees: degrees, isLevel: viewModel.isLevel)
                        .padding(.top, 12)
                }
            }
            .overlay(alignment: .bottom) {
                shutterButton.padding(.bottom, 40)
            }
            .task {
                await viewModel.observeTilt()
            }
            .sensoryFeedback(.impact(weight: .light), trigger: viewModel.isLevel) {
                _, isNowLevel in isNowLevel
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
                Button("Retake") { viewModel.retake() }
                    .buttonStyle(.borderedProminent)
                    .padding(.bottom, 40)
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
