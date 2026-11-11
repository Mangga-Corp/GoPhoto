//
//  AppPatternBackground.swift
//  gophoto
//
//  Created for GoPhoto design system.
//  Background with 4 soft purple corner circles (#9A69C9 at 20% opacity)
//  and center halftone dot grid (#EBDFF6).
//

import SwiftUI

struct AppPatternBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Color.white

                // Halftone dots pattern di tengah (#EBDFF6)
                CenterHalftoneDots(size: size)

                // 4 Lingkaran ungu (#9A69C9, opacity 20%) di sudut/tepi
                // Top-Left
                Circle()
                    .fill(Color(hex: 0x9A69C9).opacity(0.20))
                    .frame(width: size.width * 0.65, height: size.width * 0.65)
                    .blur(radius: 35)
                    .position(x: size.width * 0.1, y: size.height * 0.05)

                // Top-Right
                Circle()
                    .fill(Color(hex: 0x9A69C9).opacity(0.20))
                    .frame(width: size.width * 0.65, height: size.width * 0.65)
                    .blur(radius: 35)
                    .position(x: size.width * 0.95, y: size.height * 0.12)

                // Bottom-Left
                Circle()
                    .fill(Color(hex: 0x9A69C9).opacity(0.20))
                    .frame(width: size.width * 0.70, height: size.width * 0.70)
                    .blur(radius: 40)
                    .position(x: size.width * 0.05, y: size.height * 0.92)

                // Bottom-Right
                Circle()
                    .fill(Color(hex: 0x9A69C9).opacity(0.20))
                    .frame(width: size.width * 0.70, height: size.width * 0.70)
                    .blur(radius: 40)
                    .position(x: size.width * 0.95, y: size.height * 0.85)
            }
            .clipped()
        }
        .ignoresSafeArea()
    }
}

/// Diamond / oval halftone dot pattern in center (#EBDFF6)
private struct CenterHalftoneDots: View {
    let size: CGSize
    private let dotColor = Color(hex: 0xEBDFF6)

    var body: some View {
        Canvas { context, canvasSize in
            let spacing: CGFloat = 17
            let centerX = canvasSize.width / 2
            let centerY = canvasSize.height / 2
            let maxRadiusX = canvasSize.width * 0.44
            let maxRadiusY = canvasSize.height * 0.44

            let cols = Int(canvasSize.width / spacing) + 2
            let rows = Int(canvasSize.height / spacing) + 2

            let startX = (canvasSize.width - CGFloat(cols - 1) * spacing) / 2
            let startY = (canvasSize.height - CGFloat(rows - 1) * spacing) / 2

            for row in 0..<rows {
                let y = startY + CGFloat(row) * spacing
                let dy = abs(y - centerY) / maxRadiusY

                for col in 0..<cols {
                    let x = startX + CGFloat(col) * spacing
                    let dx = abs(x - centerX) / maxRadiusX

                    let dist = sqrt(dx * dx + dy * dy)
                    if dist <= 1.0 {
                        let scale = pow(1.0 - dist, 0.75)
                        let dotRadius = max(1.2, 4.2 * scale)
                        let rect = CGRect(
                            x: x - dotRadius,
                            y: y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                }
            }
        }
    }
}

extension View {
    /// Applies the standard GoPhoto halftone pattern background
    func appPatternBackground() -> some View {
        background {
            AppPatternBackground()
        }
    }
}
