//
//  ShotSizeIllustration.swift
//  gophoto
//
//  The shot size cards' picture: a standing figure inside a dashed viewfinder with corner marks
//  that crops it at the waist (Half), mid-thigh (3/4) or below the feet (Full). Drawn with
//  SwiftUI shapes, so it scales with the card.
//

import SwiftUI

struct ShotSizeIllustration: View {
    let shot: SessionShotSize
    let isSelected: Bool

    /// Figure layout in a unit box (y down): head on top, feet at the bottom.
    private enum Figure {
        static let top: CGFloat = 0.10
        static let feet: CGFloat = 0.92
        static let waist: CGFloat = 0.50
        static let midThigh: CGFloat = 0.66
    }

    /// Where the frame's bottom edge cuts the figure.
    private var cut: CGFloat {
        switch shot {
        case .half: Figure.waist
        case .threeQuarter: Figure.midThigh
        case .full: 0.96
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let figureColor = isSelected ? GoPhotoDesign.sessionAccent : Color(white: 0.30)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(Color.white)
                          : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.96), Color(white: 0.89)],
                                                         startPoint: .top, endPoint: .bottom)))

                // Body outside the frame: faint, so the crop is visible.
                FigureShape()
                    .fill(figureColor.opacity(0.14))
                    .frame(width: size.width, height: size.height)

                // Body inside the frame: solid.
                FigureShape()
                    .fill(figureColor)
                    .frame(width: size.width, height: size.height)
                    .mask(alignment: .top) {
                        Rectangle().frame(height: size.height * cut)
                    }

                ViewfinderFrame(cut: cut)
                    .stroke(GoPhotoDesign.sessionAccent.opacity(isSelected ? 0.9 : 0.6),
                            style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                ViewfinderCorners(cut: cut)
                    .stroke(GoPhotoDesign.sessionAccent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .aspectRatio(0.86, contentMode: .fit)
        .shadow(color: .black.opacity(isSelected ? 0.06 : 0), radius: 4, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}

/// A simple standing person: round head, shoulders and torso, arms, two legs.
private struct FigureShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        // Head.
        path.addEllipse(in: CGRect(x: rect.minX + 0.42 * w, y: rect.minY + 0.10 * h, width: 0.16 * w, height: 0.14 * h))
        // Torso (shoulders to hips).
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.36 * w, y: rect.minY + 0.26 * h, width: 0.28 * w, height: 0.26 * h),
                            cornerSize: CGSize(width: 0.07 * w, height: 0.07 * w))
        // Arms.
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.28 * w, y: rect.minY + 0.27 * h, width: 0.07 * w, height: 0.24 * h),
                            cornerSize: CGSize(width: 0.035 * w, height: 0.035 * w))
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.65 * w, y: rect.minY + 0.27 * h, width: 0.07 * w, height: 0.24 * h),
                            cornerSize: CGSize(width: 0.035 * w, height: 0.035 * w))
        // Legs (hips to feet).
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.38 * w, y: rect.minY + 0.50 * h, width: 0.105 * w, height: 0.42 * h),
                            cornerSize: CGSize(width: 0.04 * w, height: 0.04 * w))
        path.addRoundedRect(in: CGRect(x: rect.minX + 0.515 * w, y: rect.minY + 0.50 * h, width: 0.105 * w, height: 0.42 * h),
                            cornerSize: CGSize(width: 0.04 * w, height: 0.04 * w))
        return path
    }
}

/// The dashed viewfinder rectangle, from just above the head to `cut`.
private struct ViewfinderFrame: Shape {
    let cut: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(frameRect(in: rect, cut: cut))
    }
}

/// Corner brackets of the viewfinder.
private struct ViewfinderCorners: Shape {
    let cut: CGFloat
    func path(in rect: CGRect) -> Path {
        let frame = frameRect(in: rect, cut: cut)
        let arm = min(frame.width, frame.height) * 0.16
        var path = Path()
        for (corner, dx, dy) in [(CGPoint(x: frame.minX, y: frame.minY), arm, arm),
                                 (CGPoint(x: frame.maxX, y: frame.minY), -arm, arm),
                                 (CGPoint(x: frame.minX, y: frame.maxY), arm, -arm),
                                 (CGPoint(x: frame.maxX, y: frame.maxY), -arm, -arm)] {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx, y: corner.y))
        }
        return path
    }
}

private func frameRect(in rect: CGRect, cut: CGFloat) -> CGRect {
    CGRect(x: rect.minX + 0.22 * rect.width, y: rect.minY + 0.06 * rect.height,
           width: 0.56 * rect.width, height: (cut - 0.06) * rect.height)
}
