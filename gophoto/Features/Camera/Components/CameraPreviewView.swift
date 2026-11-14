//
//  CameraPreviewView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//
//  CameraPreviewView.swift
//  gophoto
//

import SwiftUI
import AVFoundation
import UIKit

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// `.resizeAspect` for 3:4 (the frame's own shape: it fills the box exactly); `.resizeAspectFill`
    /// for a narrower box (9:16), which then shows the frame's centred band, no bars, no distortion.
    var videoGravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = videoGravity

        if let connection = view.previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return view
    }

    /// A ratio change only changes the layer's gravity: the session keeps running.
    func updateUIView(_ uiView: PreviewView, context: Context) {
        guard uiView.previewLayer.videoGravity != videoGravity else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        uiView.previewLayer.videoGravity = videoGravity
        CATransaction.commit()
    }

    // A UIView whose backing layer IS the camera preview layer
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
