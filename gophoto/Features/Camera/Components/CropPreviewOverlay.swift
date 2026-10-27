//
//  CropPreviewOverlay.swift
//  gophoto
//
//  Mode F: shows the part of the frame the photo will be cropped to.
//  Outside is dimmed; the edge turns green when everything is ready.
//
import SwiftUI

struct CropPreviewOverlay: View {
    /// Normalized crop (origin top-left), nil = not known yet.
    let window: CGRect?
    let isReady: Bool

    var body: some View {
        GeometryReader { geo in
            if let window {
                let rect = CGRect(x: window.minX * geo.size.width, y: window.minY * geo.size.height,
                                  width: window.width * geo.size.width, height: window.height * geo.size.height)
                ZStack {
                    // Dim everything outside the crop.
                    Path { path in
                        path.addRect(CGRect(origin: .zero, size: geo.size))
                        path.addRect(rect)
                    }
                    .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))

                    Rectangle()
                        .stroke(isReady ? Color.green : Color.white.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, dash: isReady ? [] : [8, 6]))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: window)
        .animation(.snappy, value: isReady)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
