//
//  CameraGridOverlay.swift
//  gophoto
//
//  Camera-app style grid (rule of thirds) and photo ratio (4:3 / 1:1 / 16:9). The sensor shoots
//  4:3; other ratios are a centred crop of it, dimmed outside in the preview and cropped on save.
//

import SwiftUI

nonisolated enum CaptureAspect: String, CaseIterable, Sendable {
    case fourThree, square, sixteenNine

    static let storageKey = "captureAspect"

    /// Width / height of the upright (portrait) photo.
    var ratio: Double {
        switch self {
        case .fourThree: 3.0 / 4.0
        case .square: 1
        case .sixteenNine: 9.0 / 16.0
        }
    }

    var title: String {
        switch self {
        case .fourThree: "4:3"
        case .square: "1:1"
        case .sixteenNine: "16:9"
        }
    }

    var next: CaptureAspect {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    /// The centred rect of this ratio inside `size`.
    func rect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let r = CGFloat(ratio)
        if size.width / size.height > r {
            let w = size.height * r
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
        let h = size.width / r
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
}

/// Dims the preview outside the chosen ratio and draws the thirds grid inside it.
struct CameraGridOverlay: View {
    let aspect: CaptureAspect
    let showsGrid: Bool

    var body: some View {
        GeometryReader { geo in
            let frame = aspect.rect(in: geo.size)
            ZStack {
                if aspect != .fourThree {
                    Path { p in
                        p.addRect(CGRect(origin: .zero, size: geo.size))
                        p.addRect(frame)
                    }
                    .fill(Color.black.opacity(0.75), style: FillStyle(eoFill: true))
                }
                if showsGrid {
                    Path { p in
                        for i in 1...2 {
                            let x = frame.minX + frame.width * CGFloat(i) / 3
                            let y = frame.minY + frame.height * CGFloat(i) / 3
                            p.move(to: CGPoint(x: x, y: frame.minY)); p.addLine(to: CGPoint(x: x, y: frame.maxY))
                            p.move(to: CGPoint(x: frame.minX, y: y)); p.addLine(to: CGPoint(x: frame.maxX, y: y))
                        }
                    }
                    .stroke(Color.white.opacity(0.45), lineWidth: 0.75)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
