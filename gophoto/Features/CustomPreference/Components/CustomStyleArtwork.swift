//
//  CustomStyleArtwork.swift
//  gophoto
//
//  The picture on each custom preference card. A photo from the asset catalog
//  (`CustomStyleOption.photoAssetName`) is shown when the app bundles one; otherwise an
//  illustration drawn from the same geometry the camera guides with.
//

import SwiftUI
import UIKit

/// The option's photo, or `fallback` when the asset catalog has none.
struct CustomStyleOptionPhoto<Option: CustomStyleOption, Fallback: View>: View {
    let option: Option
    @ViewBuilder let fallback: () -> Fallback

    var body: some View {
        if let photo = UIImage(named: option.photoAssetName) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
        } else {
            fallback()
        }
    }
}

// MARK: - Subject placement

/// A portrait frame with the thirds grid and a person placed like the camera will guide them.
struct SubjectPlacementArtwork: View {
    let placement: SubjectPlacement

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let box = CustomPresetAnalysisFactory.subjectBox(for: placement)
            ZStack {
                ArtworkScenery()
                ThirdsGrid(highlightsIntersections: placement == .ruleOfThirds)
                Image(systemName: "figure.stand")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(GoPhotoDesign.primary)
                    .frame(width: box.width * size.width, height: box.height * size.height)
                    .position(x: box.midX * size.width, y: box.midY * size.height)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct ThirdsGrid: View {
    let highlightsIntersections: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            let thirdsX = [width / 3, width * 2 / 3], thirdsY = [height / 3, height * 2 / 3]
            ZStack {
                Path { path in
                    for x in thirdsX {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    for y in thirdsY {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if highlightsIntersections {
                    ForEach(thirdsX, id: \.self) { x in
                        ForEach(thirdsY, id: \.self) { y in
                            Circle()
                                .fill(GoPhotoDesign.onPrimary)
                                .overlay(Circle().strokeBorder(GoPhotoDesign.primary, lineWidth: 1.5))
                                .frame(width: 8, height: 8)
                                .position(x: x, y: y)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Camera angle

/// A side view: the subject on the right, the camera where this angle puts it and its line of sight.
struct CameraAngleArtwork: View {
    let angle: CameraAngleStyle

    /// The subject (normalized, origin top-left) and the point the camera looks at (the face).
    private static let groundY = 0.9
    private static let subjectBox = CGRect(x: 0.56, y: 0.3, width: 0.26, height: 0.6)
    private static let face = CGPoint(x: 0.69, y: 0.36)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let camera = scaled(cameraPosition, size)
            let face = scaled(Self.face, size)
            let sightAngle = Angle(radians: atan2(face.y - camera.y, face.x - camera.x))
            ZStack {
                ArtworkScenery(groundY: Self.groundY)

                Image(systemName: "figure.stand")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(GoPhotoDesign.primary)
                    .frame(width: Self.subjectBox.width * size.width, height: Self.subjectBox.height * size.height)
                    .position(x: Self.subjectBox.midX * size.width, y: Self.subjectBox.midY * size.height)

                Path { path in
                    path.move(to: camera)
                    path.addLine(to: face)
                }
                .stroke(GoPhotoDesign.tagText, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4]))

                Image(systemName: "camera.fill")
                    .font(AppFont.system(size: min(size.width, size.height) * 0.16))
                    .foregroundStyle(GoPhotoDesign.tagText)
                    .rotationEffect(sightAngle)
                    .position(camera)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// Where the camera sits for this angle (normalized, origin top-left).
    private var cameraPosition: CGPoint {
        switch angle {
        case .eyeLevel: CGPoint(x: 0.18, y: Self.face.y)
        case .lowAngle: CGPoint(x: 0.2, y: 0.68)
        case .highAngle: CGPoint(x: 0.2, y: 0.1)
        }
    }

    private func scaled(_ point: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

// MARK: - Shared scenery

/// Sky and ground behind the illustrations.
private struct ArtworkScenery: View {
    var groundY: CGFloat = 0.86

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                LinearGradient(colors: [GoPhotoDesign.primaryBorder, GoPhotoDesign.primarySubtle],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: geometry.size.height * groundY)
                GoPhotoDesign.secondaryBackground
            }
        }
    }
}

// MARK: - Preference list thumbnail

/// A custom preference's thumbnail on Preference Selection: its placement, with its angle as a badge.
struct CustomPreferenceThumbnail: View {
    let style: CustomPreferenceStyle
    var size = CGSize(width: 84, height: 100)

    var body: some View {
        CustomStyleOptionPhoto(option: style.placement) {
            SubjectPlacementArtwork(placement: style.placement)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: style.angle.symbolName)
                .font(AppFont.system(size: 11, weight: .semibold))
                .foregroundStyle(GoPhotoDesign.onPrimary)
                .frame(width: 24, height: 24)
                .background(GoPhotoDesign.primary, in: Circle())
                .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}

extension CameraAngleStyle {
    /// Badge symbol on the preference list thumbnail.
    var symbolName: String {
        switch self {
        case .eyeLevel: "eye"
        case .lowAngle: "arrow.up.forward"
        case .highAngle: "arrow.down.forward"
        }
    }
}

#Preview("Placements") {
    ScrollView(.horizontal) {
        HStack {
            ForEach(SubjectPlacement.allCases) { placement in
                SubjectPlacementArtwork(placement: placement).frame(width: 120, height: 160)
            }
        }
    }
}

#Preview("Angles") {
    ScrollView(.horizontal) {
        HStack {
            ForEach(CameraAngleStyle.allCases) { angle in
                CameraAngleArtwork(angle: angle).frame(width: 120, height: 160)
            }
        }
    }
}
