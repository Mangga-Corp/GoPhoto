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

    static let tiltView: TiltView = .angledRight45   // yaw -45°: phone turned 45°, screen facing left
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

/// Height: a slim straight arrow (up = raise the phone, down = lower it).
struct RacingArrowView: View {
    let direction: RacingArrowDirection
    var color: Color = GuidanceAnimationStyle.arrowColor

    var body: some View {
        MinimalGuidanceArrow(pointsUp: direction == .up, curve: 0, color: color)
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

/// Tilt: the same slim arrow with a gentle bow, to say "turn", not "move".
/// Up = aim the phone higher, down = aim it lower. It only ever points up or down, so it can't be
/// read as left / right. The caller puts it above the phone for up and below it for down.
struct CurvedRacingArrowView: View {
    let direction: Direction
    var color: Color = GuidanceAnimationStyle.arrowColor
    var speedMultiplier: Double = 1.0

    var body: some View {
        MinimalGuidanceArrow(pointsUp: direction == .up, curve: 0, color: color, speed: speedMultiplier)
    }
}

/// A thin, elegant arrow that draws itself along its line, holds, and fades; repeats.
/// `curve` bows the line sideways (points); 0 = straight.
struct MinimalGuidanceArrow: View {
    let pointsUp: Bool
    var curve: CGFloat = 0
    var color: Color = GuidanceAnimationStyle.arrowColor
    var speed: Double = 1.0

    private let cycle: Double = 1.35
    private let size = CGSize(width: 40, height: 64)

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speed
            let phase = time.truncatingRemainder(dividingBy: cycle) / cycle
            Canvas { context, canvasSize in
                draw(&context, in: canvasSize, phase: phase)
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Loading-style flow: a bright comet runs from tail to tip over a faint track, then the
    /// arrowhead pulses as it arrives. Loops continuously.
    private func draw(_ context: inout GraphicsContext, in canvasSize: CGSize, phase: Double) {
        let margin: CGFloat = 6
        let tail = CGPoint(x: canvasSize.width / 2, y: pointsUp ? canvasSize.height - margin : margin)
        let tip = CGPoint(x: canvasSize.width / 2, y: pointsUp ? margin : canvasSize.height - margin)
        let control = CGPoint(x: canvasSize.width / 2 + curve, y: (tail.y + tip.y) / 2)

        func point(_ t: CGFloat) -> CGPoint {
            let u = 1 - t
            return CGPoint(x: u * u * tail.x + 2 * u * t * control.x + t * t * tip.x,
                           y: u * u * tail.y + 2 * u * t * control.y + t * t * tip.y)
        }
        func path(from a: CGFloat, to b: CGFloat) -> Path {
            var p = Path()
            let steps = 28
            p.move(to: point(a))
            for i in 1...steps { p.addLine(to: point(a + (b - a) * CGFloat(i) / CGFloat(steps))) }
            return p
        }

        let head = CGFloat(min(phase * 1.25, 1))
        let trail = CGFloat(max(0, (phase - 0.4) * 1.25))
        let arrival = max(0, min(1, (phase - 0.6) / 0.4))
        let pulse = 0.45 + 0.55 * sin(arrival * .pi)

        var layer = context
        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1))

        // Faint static track.
        layer.stroke(path(from: 0, to: 1), with: .color(color.opacity(0.25)),
                     style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

        // Flowing comet: three segments, brighter toward the head.
        if head > trail + 0.01 {
            for i in 0..<3 {
                let s0 = trail + (head - trail) * CGFloat(i) / 3
                let s1 = trail + (head - trail) * CGFloat(i + 1) / 3
                layer.stroke(path(from: s0, to: s1),
                             with: .color(color.opacity(0.35 + 0.325 * Double(i + 1))),
                             style: StrokeStyle(lineWidth: 3.2 + 0.6 * CGFloat(i), lineCap: .round))
            }
        }

        // Filled chevron head at the tip, pulsing on arrival.
        let dir: CGFloat = pointsUp ? -1 : 1
        let end = tip
        var chevron = Path()
        chevron.move(to: CGPoint(x: end.x, y: end.y + dir * 3))
        chevron.addLine(to: CGPoint(x: end.x - 9, y: end.y - dir * 8))
        chevron.addLine(to: CGPoint(x: end.x, y: end.y - dir * 4))
        chevron.addLine(to: CGPoint(x: end.x + 9, y: end.y - dir * 8))
        chevron.closeSubpath()
        layer.opacity = pulse
        layer.addFilter(.shadow(color: color.opacity(0.7), radius: 4))
        layer.fill(chevron, with: .color(color))
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
        let spacing: CGFloat = 34
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
