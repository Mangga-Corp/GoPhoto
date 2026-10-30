import SwiftUI

struct WelcomeGalleryView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(Self.tracks) { track in
                    DiagonalGalleryTrack(track: track, viewport: geometry.size)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.72), location: 0.48),
                        .init(color: .white, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: geometry.size.height * 0.30)
                .allowsHitTesting(false)
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }

    private static let tracks: [GalleryTrack] = [
        GalleryTrack(
            id: "left",
            centerFraction: 0.02,
            phase: 0.25,
            slope: 0.22,
            duration: 52,
            movesUpLeft: true,
            cards: [
                .init(asset: "OnboardingPhoto01", rotationVariation: -0.48, stagger: -2),
                .init(asset: "OnboardingPhoto05", rotationVariation: 0.64, stagger: 1),
                .init(asset: "OnboardingPhoto08", rotationVariation: -0.20, stagger: 2),
                .init(asset: "OnboardingPhoto11", rotationVariation: 0.36, stagger: -1),
                .init(asset: "OnboardingPhoto14", rotationVariation: -0.72, stagger: 1),
                .init(asset: "OnboardingPhoto17", rotationVariation: 0.44, stagger: -2),
                .init(asset: "OnboardingPhoto20", rotationVariation: -0.32, stagger: 2),
                .init(asset: "OnboardingPhoto23", rotationVariation: 0.76, stagger: -1),
                .init(asset: "OnboardingPhoto26", rotationVariation: -0.56, stagger: 1),
                .init(asset: "OnboardingPhoto29", rotationVariation: 0.24, stagger: -2)
            ]
        ),
        GalleryTrack(
            id: "center",
            centerFraction: 0.5,
            phase: 0.25,
            slope: 0.22,
            duration: 80,
            movesUpLeft: false,
            cards: [
                .init(asset: "OnboardingPhoto02", rotationVariation: 0.52, stagger: 1),
                .init(asset: "OnboardingPhoto06", rotationVariation: -0.64, stagger: -2),
                .init(asset: "OnboardingPhoto09", rotationVariation: 0.16, stagger: 2),
                .init(asset: "OnboardingPhoto12", rotationVariation: -0.36, stagger: -1),
                .init(asset: "OnboardingPhoto15", rotationVariation: 0.72, stagger: 1),
                .init(asset: "OnboardingPhoto18", rotationVariation: -0.44, stagger: -2),
                .init(asset: "OnboardingPhoto21", rotationVariation: 0.32, stagger: 2),
                .init(asset: "OnboardingPhoto24", rotationVariation: -0.76, stagger: -1),
                .init(asset: "OnboardingPhoto27", rotationVariation: 0.56, stagger: 1),
                .init(asset: "OnboardingPhoto30", rotationVariation: -0.24, stagger: -2)
            ]
        ),
        GalleryTrack(
            id: "right",
            centerFraction: 0.98,
            phase: 0.25,
            slope: 0.22,
            duration: 38,
            movesUpLeft: true,
            cards: [
                .init(asset: "OnboardingPhoto03", rotationVariation: -0.44, stagger: -2),
                .init(asset: "OnboardingPhoto04", rotationVariation: 0.72, stagger: 1),
                .init(asset: "OnboardingPhoto07", rotationVariation: -0.16, stagger: 2),
                .init(asset: "OnboardingPhoto10", rotationVariation: 0.48, stagger: -1),
                .init(asset: "OnboardingPhoto13", rotationVariation: -0.68, stagger: 1),
                .init(asset: "OnboardingPhoto16", rotationVariation: 0.28, stagger: -2),
                .init(asset: "OnboardingPhoto19", rotationVariation: -0.52, stagger: 2),
                .init(asset: "OnboardingPhoto22", rotationVariation: 0.64, stagger: -1),
                .init(asset: "OnboardingPhoto25", rotationVariation: -0.32, stagger: 1),
                .init(asset: "OnboardingPhoto28", rotationVariation: 0.20, stagger: -2)
            ]
        )
    ]
}

private struct GalleryTrack: Identifiable {
    let id: String
    let centerFraction: CGFloat
    let phase: CGFloat
    let slope: CGFloat
    let duration: Double
    let movesUpLeft: Bool
    let cards: [GalleryCardSpec]
}

private struct GalleryCardSpec: Identifiable {
    let asset: String
    let rotationVariation: Double
    let stagger: CGFloat
    var id: String { asset }
}

private enum GalleryCardLayout {
    static let widthFraction: CGFloat = 0.43
    static let aspectRatio: CGFloat = 4.0 / 3.0
    static let cornerRadius: CGFloat = 15
    static let verticalGap: CGFloat = 15

    static func size(in viewport: CGSize) -> CGSize {
        let width = viewport.width * widthFraction
        return CGSize(width: width, height: width * aspectRatio)
    }
}

private struct DiagonalGalleryTrack: View {
    let track: GalleryTrack
    let viewport: CGSize
    @State private var progress: CGFloat = 0

    var body: some View {
        let cardSize = GalleryCardLayout.size(in: viewport)
        let cardWidth = cardSize.width
        let cardHeight = cardSize.height
        let diagonalAngle = atan(Double(track.slope))
        let diagonalCosine = CGFloat(cos(diagonalAngle))
        let trackHalfExtent = track.cards.map { card in
            let variation = card.rotationVariation * .pi / 180
            return (cardHeight * CGFloat(abs(cos(variation)))
                + cardWidth * CGFloat(abs(sin(variation)))) / 2
        }
        let trackSteps = track.cards.indices.map { index in
            let nextIndex = (index + 1) % track.cards.count
            let distanceAlongTrack = trackHalfExtent[index]
                + trackHalfExtent[nextIndex]
                + GalleryCardLayout.verticalGap
            return distanceAlongTrack * diagonalCosine
        }
        let cycleHeight = trackSteps.reduce(0, +)
        let cycleStart = -cycleHeight * track.phase
        let direction: CGFloat = track.movesUpLeft ? -1 : 1
        let cycleOffset = direction * progress * cycleHeight
        let copyRange = -2...2

        ZStack {
            ForEach(copyRange, id: \.self) { copy in
                ForEach(track.cards.indices, id: \.self) { index in
                    let precedingHeight = trackSteps.prefix(index).reduce(CGFloat.zero, +)
                    let centerY = cycleStart + CGFloat(copy) * cycleHeight + precedingHeight
                    let centerX = viewport.width * track.centerFraction
                        + track.slope * centerY
                        + track.cards[index].stagger
                    let animatedY = centerY + cycleOffset
                    let animatedX = centerX + track.slope * cycleOffset

                    GalleryPhotoCard(
                        spec: track.cards[index],
                        size: cardSize,
                        diagonalBaseRotation: -diagonalAngle * 180 / .pi
                    )
                    .position(x: animatedX, y: animatedY)
                    .zIndex(Double(index) / 100 + Double(copy))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: track.duration).repeatForever(autoreverses: false)) {
                progress = 1
            }
        }
    }
}

private struct GalleryPhotoCard: View {
    let spec: GalleryCardSpec
    let size: CGSize
    let diagonalBaseRotation: Double

    var body: some View {
        Image(spec.asset)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: GalleryCardLayout.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 7, x: 0, y: 4)
            .rotationEffect(.degrees(diagonalBaseRotation + spec.rotationVariation))
    }
}
