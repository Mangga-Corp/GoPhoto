//
//  GuidanceMotionOverlay.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

import SwiftUI
import UIKit

// MARK: - Pengaturan Animasi & Tampilan (Ukuran HP & Kegelapan Layar)

enum GuidanceAnimationStyle {
    static let sizeFraction: CGFloat = 0.35
    static let dimOpacity: Double = 0.60

    //timing
    static let visibleDuration: Double = 2.5   //animasi muncul
    static let intervalDuration: Double = 2.0  //jeda sebelum masuk lagi
    static let fadeDuration: Double = 0.3

    //visual hengpong
    static let lineWidth: Float = 0.0016
    static let phoneColor = UIColor.white

    //view lagi nih
    static let guideColor = UIColor(red: 0.98, green: 0.78, blue: 0.46, alpha: 1)
    static let arrowColor = Color(red: 0.98, green: 0.78, blue: 0.46)

    static let tiltView: TiltView = .angledRight45
    static let heightYawDegrees: Double = -20
    static let tiltStepDegrees: Double = 5
}

// MARK: - Racing Chevron Arrow Component

enum RacingArrowDirection {
    case up
    case down

    var rotation: Angle {
        switch self {
        case .down:  .degrees(90)
        case .up:    .degrees(-90)
        }
    }
}

/// Bentuk chevron tajam bergaya game balap mobil
struct RacingChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let tipX = w
        let midY = h / 2
        let thickness = w * 0.44

        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: thickness, y: 0))
        path.addLine(to: CGPoint(x: tipX, y: midY))
        path.addLine(to: CGPoint(x: thickness, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: tipX - thickness, y: midY))
        path.closeSubpath()

        return path
    }
}

/// Deretan 3 racing chevron bertingkat asli untuk height (tidak diganti)
struct RacingArrowView: View {
    let direction: RacingArrowDirection
    var color: Color = GuidanceAnimationStyle.arrowColor

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let progress = (time.truncatingRemainder(dividingBy: 0.85)) / 0.85

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    let chevronOffset = Double(index) / 3.0
                    let localPhase = (progress - chevronOffset + 1.0).truncatingRemainder(dividingBy: 1.0)
                    let brightness = 0.35 + 0.65 * pow(sin(localPhase * .pi), 2)

                    RacingChevronShape()
                        .fill(
                            LinearGradient(
                                colors: [
                                    color.opacity(min(brightness * 1.25, 1.0)),
                                    color.opacity(brightness * 0.75)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 14, height: 22)
                        .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
                        .scaleEffect(0.90 + 0.10 * brightness)
                }
            }
            .rotationEffect(direction.rotation)
        }
    }
}

/// Helper konfigurasi tiap chevron tunggal dengan efek loading (bentuk & tebal persis seperti aslinya)
struct RacingChevronItem: View {
    let brightness: Double
    var color: Color = GuidanceAnimationStyle.arrowColor

    var body: some View {
        RacingChevronShape()
            .fill(
                LinearGradient(
                    colors: [
                        color.opacity(min(brightness * 1.25, 1.0)),
                        color.opacity(brightness * 0.75)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 14, height: 22)
            .shadow(color: Color.black.opacity(0.45), radius: 3, x: 0, y: 1)
            .scaleEffect(0.90 + 0.10 * brightness)
    }
}

/// Arrow melengkung diatas HP HANYA saat tilting dengan 3 racing chevron yang melengkung mengikuti arah tilt
/// dan animasi bertahap seperti loading yang looping selama bimbingan muncul.
struct CurvedRacingArrowView: View {
    let direction: Direction
    var color: Color = GuidanceAnimationStyle.arrowColor
    var speedMultiplier: Double = 1.0

    // Siklus animasi yang tidak terlalu cepat dan tidak terlalu pelan (~1.3 detik)
    private let cycleDuration: Double = 1.30

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speedMultiplier
            let progress = (time.truncatingRemainder(dividingBy: cycleDuration)) / cycleDuration

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    // Animasi seperti loading: chevron menyala berurutan (0 -> 1 -> 2)
                    let start = Double(index) * 0.22
                    let localPhase = max(0.0, min(1.0, (progress - start) / 0.45))
                    let brightness = 0.25 + 0.75 * sin(localPhase * .pi)

                    let (offset, rotation) = chevronTransform(for: index, direction: direction)

                    RacingChevronItem(brightness: brightness, color: color)
                        .rotationEffect(rotation)
                        .offset(offset)
                }
            }
            .frame(width: 80, height: 44)
        }
    }

    /// Menghitung posisi dan rotasi masing-masing chevron agar melengkung ke kanan-bawah atau kiri-bawah (tidak ada yang ke atas)
    private func chevronTransform(for index: Int, direction: Direction) -> (CGSize, Angle) {
        switch direction {
        case .down:
            // Melengkung ke KANAN BAWAH (mengalir dari atas-kiri ke kanan-bawah)
            switch index {
            case 0: return (CGSize(width: -20, height: -8), .degrees(20))
            case 1: return (CGSize(width: 0, height: -2), .degrees(45))
            case 2: return (CGSize(width: 20, height: 8), .degrees(70))
            default: return (.zero, .zero)
            }
        case .up:
            // Melengkung ke KIRI BAWAH (mengalir dari atas-kanan ke kiri-bawah, tidak ada yang ke atas)
            switch index {
            case 0: return (CGSize(width: 20, height: -8), .degrees(160))
            case 1: return (CGSize(width: 0, height: -2), .degrees(135))
            case 2: return (CGSize(width: -20, height: 8), .degrees(110))
            default: return (.zero, .zero)
            }
        }
    }
}

// MARK: - Main Guidance Overlay

struct GuidanceMotionOverlay: View {
    let instruction: GuideInstruction
    /// Phone pitch minus target, degrees (CameraViewModel.pitchError).
    let pitchError: Double?
    /// False while something covers the camera (gallery, analysis sheet).
    var isEnabled: Bool = true

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAnimationVisible: Bool = false

    private var motion: GuidanceMotion? {
        guard isEnabled, scenePhase == .active else { return nil }
        let step = GuidanceAnimationStyle.tiltStepDegrees
        let steppedError = pitchError.map { ($0 / step).rounded() * step }
        return GuidanceMotion(instruction: instruction, pitchError: steppedError,
                              tiltView: GuidanceAnimationStyle.tiltView)
    }

    private struct CycleTrigger: Equatable {
        let instruction: GuideInstruction
        let isEnabled: Bool
        let isActive: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let fraction = min(max(GuidanceAnimationStyle.sizeFraction, 0.15), 0.5)
            let height = proxy.size.height * fraction
            let width = height * 0.72

            // Posisi tepat di garis antara kotak guideline kiri dan tengah (rule of thirds: x = 1/3)
            let gridLineX = proxy.size.width / 3.0
            let centerY = proxy.size.height / 2.0

            ZStack {
                // 1. Layar digelapkan sedikit (muncul & hilang BARENGAN dengan animasi 3D)
                if isAnimationVisible && motion != nil {
                    Color.black.opacity(GuidanceAnimationStyle.dimOpacity)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // 2. 3D Mockup Phone
                if isAnimationVisible, let motion {
                    animation(for: motion)
                        .frame(width: width, height: height)
                        .position(x: gridLineX, y: centerY)
                        .transition(.opacity)
                }

                // 3. Dynamic Arrow:
                // - Saat tilting: arrow berada DI ATASNYA dan MELENGKUNG mengikuti arah tilting (menempel lebih dekat)
                // - Saat height: arrow asli sebelumnya (tidak diganti)
                if isAnimationVisible, let motion {
                    switch motion {
                    case .tilt(let direction, _, _):
                        CurvedRacingArrowView(direction: direction)
                            .position(x: gridLineX, y: centerY - (height / 2) - 10)
                            .transition(.opacity)

                    case .height(let direction):
                        let arrowDir: RacingArrowDirection = (direction == .up) ? .up : .down
                        let pos = arrowPosition(for: arrowDir, phoneX: gridLineX, phoneY: centerY,
                                                phoneWidth: width, phoneHeight: height)
                        RacingArrowView(direction: arrowDir)
                            .position(pos)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: CycleTrigger(instruction: instruction, isEnabled: isEnabled, isActive: scenePhase == .active)) {
            await runGuidanceCycle()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func animation(for motion: GuidanceMotion) -> some View {
        switch motion {
        case .height(let direction):
            HeightGuidanceView(direction: direction,
                               isActive: isAnimationVisible && !reduceMotion,
                               yawDegrees: GuidanceAnimationStyle.heightYawDegrees,
                               guideColor: GuidanceAnimationStyle.guideColor,
                               showsStillPose: reduceMotion)
                .id("height-\(direction)")
        case .tilt(let direction, let degrees, let view):
            TiltGuidanceView(direction: direction,
                             degrees: degrees,
                             tiltView: view,
                             isActive: isAnimationVisible && !reduceMotion,
                             guideColor: GuidanceAnimationStyle.guideColor,
                             showsStillPose: reduceMotion)
                .id("tilt-\(direction)")
        }
    }

    // MARK: - Arrow Positioning Helper untuk Height (asli sebelumnya)

    private func arrowPosition(
        for direction: RacingArrowDirection,
        phoneX: CGFloat,
        phoneY: CGFloat,
        phoneWidth: CGFloat,
        phoneHeight: CGFloat
    ) -> CGPoint {
        let spacing: CGFloat = 26
        switch direction {
        case .up:
            // Panah naik diatas handphone
            return CGPoint(x: phoneX, y: phoneY - (phoneHeight / 2) - spacing)
        case .down:
            // Panah turun dibawah handphone
            return CGPoint(x: phoneX, y: phoneY + (phoneHeight / 2) + spacing)
        }
    }

    // MARK: - Cycle Timing Logic

    @MainActor
    private func runGuidanceCycle() async {
        guard isEnabled, scenePhase == .active, motion != nil else {
            withAnimation(.easeInOut(duration: GuidanceAnimationStyle.fadeDuration)) {
                isAnimationVisible = false
            }
            return
        }

        while !Task.isCancelled {
            // Cek apakah instruksi saat ini masih membutuhkan bimbingan gerak
            guard isEnabled, scenePhase == .active, motion != nil else {
                withAnimation(.easeInOut(duration: GuidanceAnimationStyle.fadeDuration)) {
                    isAnimationVisible = false
                }
                break
            }

            // 1. Munculkan animasi + arrow + gelapkan layar bersamaan
            withAnimation(.easeInOut(duration: GuidanceAnimationStyle.fadeDuration)) {
                isAnimationVisible = true
            }

            // Animasi aktif selama 2.5 detik
            do {
                let ms = UInt64(GuidanceAnimationStyle.visibleDuration * 1000)
                try await Task.sleep(for: .milliseconds(ms))
            } catch {
                break
            }

            // 2. Layar kembali normal tanpa opacity dan animasi (berbarengan)
            withAnimation(.easeInOut(duration: GuidanceAnimationStyle.fadeDuration)) {
                isAnimationVisible = false
            }

            // Jeda 2.0 detik sebelum muncul lagi jika user belum mencapai referensi/guide
            do {
                let ms = UInt64(GuidanceAnimationStyle.intervalDuration * 1000)
                try await Task.sleep(for: .milliseconds(ms))
            } catch {
                break
            }
        }

        // Cleanup: jika task dibatalkan (misal target tercapai), kembalikan layar normal
        withAnimation(.easeInOut(duration: GuidanceAnimationStyle.fadeDuration)) {
            isAnimationVisible = false
        }
    }
}
