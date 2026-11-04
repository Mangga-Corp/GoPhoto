//
//  GuidanceLoadingArrowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 30/10/26.
//

import SwiftUI

// MARK: - Shared Arrow Style Constants

enum GuidanceArrowStyle {
    static let color = Color(red: 0.98, green: 0.78, blue: 0.46) // Warm gold
    static let trackOpacity = 0.22
    static let cycleDuration: Double = 1.35 // "Jangan terlalu cepat dan jangan terlalu pelan"
    static let lineWidth: CGFloat = 4.0
    static let arrowHeadLength: CGFloat = 12.0
    static let arrowHeadWidth: CGFloat = 11.0
}

// MARK: - Curved Arc Geometry for Tilting

/// Bentuk busur melengkung mengikuti trajektori rotasi HP dalam perspektif miring ke kanan (45° yaw).
/// - `.down` (tilt down / condong ke depan): melengkung dari kiri-atas (belakang) ke kanan-bawah (depan).
/// - `.up`   (tilt up / condong ke belakang): melengkung dari kanan-bawah (depan) ke kiri-atas (belakang).
struct CurvedTiltArcShape: Shape {
    let direction: Direction

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        switch direction {
        case .down:
            // Dari belakang (kiri atas) membusur ke depan (kanan bawah)
            let start = CGPoint(x: w * 0.16, y: h * 0.28)
            let end = CGPoint(x: w * 0.82, y: h * 0.72)
            let control = CGPoint(x: w * 0.58, y: h * 0.08)
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)

        case .up:
            // Dari depan (kanan bawah) membusur ke belakang (kiri atas)
            let start = CGPoint(x: w * 0.84, y: h * 0.68)
            let end = CGPoint(x: w * 0.18, y: h * 0.24)
            let control = CGPoint(x: w * 0.42, y: h * 0.88)
            path.move(to: start)
            path.addQuadCurve(to: end, control: control)
        }

        return path
    }

    /// Koordinat ujung dan sudut tangensial panah untuk menggambar kepala panah (arrowhead)
    func endVector(in rect: CGRect) -> (point: CGPoint, angle: Angle) {
        let w = rect.width
        let h = rect.height

        switch direction {
        case .down:
            let end = CGPoint(x: w * 0.82, y: h * 0.72)
            let control = CGPoint(x: w * 0.58, y: h * 0.08)
            let dx = end.x - control.x
            let dy = end.y - control.y
            let angle = Angle(radians: atan2(dy, dx))
            return (end, angle)

        case .up:
            let end = CGPoint(x: w * 0.18, y: h * 0.24)
            let control = CGPoint(x: w * 0.42, y: h * 0.88)
            let dx = end.x - control.x
            let dy = end.y - control.y
            let angle = Angle(radians: atan2(dy, dx))
            return (end, angle)
        }
    }
}

// MARK: - Arrow Head Shape

struct ArrowHeadPolygon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w, y: h / 2))           // Ujung runcing panah
        path.addLine(to: CGPoint(x: 0, y: 0))           // Sayap atas
        path.addLine(to: CGPoint(x: w * 0.28, y: h / 2)) // Lekukan dalam
        path.addLine(to: CGPoint(x: 0, y: h))           // Sayap bawah
        path.closeSubpath()

        return path
    }
}

// MARK: - Curved Tilt Loading Arrow View

/// Arrow melengkung tepat di atas HP saat tilting dengan animasi loading yang mengalir looping
struct CurvedTiltArrowView: View {
    let direction: Direction
    var color: Color = GuidanceArrowStyle.color
    var speedMultiplier: Double = 1.0

    private let canvasWidth: CGFloat = 86
    private let canvasHeight: CGFloat = 46

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speedMultiplier
            let duration = GuidanceArrowStyle.cycleDuration
            let progress = (time.truncatingRemainder(dividingBy: duration)) / duration

            // Gelombang loading mengalir dari 0.0 sampai 1.0
            // Head menyala dan memanjang saat bergerak
            let strokeHead = min(progress * 1.25, 1.0)
            let strokeTail = max(0.0, (progress - 0.40) * 1.25)

            // Pulse cahaya pada ujung kepala panah saat gelombang loading mencapai ujung
            let tipArrival = max(0.0, min(1.0, (progress - 0.60) / 0.40))
            let tipBrightness = 0.45 + 0.55 * sin(tipArrival * .pi)

            let shape = CurvedTiltArcShape(direction: direction)
            let rect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
            let tip = shape.endVector(in: rect)

            ZStack {
                // 1. Jalur dasar (track) statis tipis transparan
                shape
                    .stroke(
                        color.opacity(GuidanceArrowStyle.trackOpacity),
                        style: StrokeStyle(lineWidth: GuidanceArrowStyle.lineWidth, lineCap: .round)
                    )

                // 2. Stroke loading yang mengalir (trim dari tail sampai head)
                shape
                    .trim(from: strokeTail, to: strokeHead)
                    .stroke(
                        LinearGradient(
                            colors: [
                                color.opacity(0.15),
                                color.opacity(0.85),
                                color
                            ],
                            startPoint: direction == .down ? .topLeading : .bottomTrailing,
                            endPoint: direction == .down ? .bottomTrailing : .topLeading
                        ),
                        style: StrokeStyle(lineWidth: GuidanceArrowStyle.lineWidth + 0.8, lineCap: .round)
                    )
                    .shadow(color: color.opacity(0.6), radius: 4, x: 0, y: 0)

                // 3. Kepala panah di ujung busur yang ikut bereaksi saat aliran loading sampai
                ArrowHeadPolygon()
                    .fill(color.opacity(tipBrightness))
                    .frame(width: GuidanceArrowStyle.arrowHeadLength, height: GuidanceArrowStyle.arrowHeadWidth)
                    .rotationEffect(tip.angle)
                    .position(tip.point)
                    .shadow(color: color.opacity(tipBrightness * 0.7), radius: 3, x: 0, y: 0)
                    .scaleEffect(0.92 + 0.12 * tipBrightness)
            }
            .frame(width: canvasWidth, height: canvasHeight)
        }
    }
}

// MARK: - Straight Height Loading Arrow View

/// Arrow lurus untuk bimbingan ketinggian (naik / turun) dengan animasi loading berulang
struct HeightLoadingArrowView: View {
    let direction: Direction
    var color: Color = GuidanceArrowStyle.color
    var speedMultiplier: Double = 1.0

    private let length: CGFloat = 50
    private let width: CGFloat = 24

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speedMultiplier
            let duration = GuidanceArrowStyle.cycleDuration
            let progress = (time.truncatingRemainder(dividingBy: duration)) / duration

            // Loading flow dari pangkal batang menuju ke kepala panah
            let strokeHead = min(progress * 1.25, 1.0)
            let strokeTail = max(0.0, (progress - 0.40) * 1.25)

            // Respon kepala panah saat loading tiba
            let tipArrival = max(0.0, min(1.0, (progress - 0.60) / 0.40))
            let tipBrightness = 0.45 + 0.55 * sin(tipArrival * .pi)

            VStack(spacing: 0) {
                if direction == .up {
                    // Panah mengarah ke atas: Kepala di atas, batang di bawah
                    ArrowHeadPolygon()
                        .fill(color.opacity(tipBrightness))
                        .frame(width: GuidanceArrowStyle.arrowHeadLength, height: GuidanceArrowStyle.arrowHeadWidth)
                        .rotationEffect(.degrees(-90))
                        .scaleEffect(0.92 + 0.14 * tipBrightness)
                        .shadow(color: color.opacity(tipBrightness * 0.7), radius: 3)

                    ZStack(alignment: .bottom) {
                        // Jalur track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(GuidanceArrowStyle.trackOpacity))
                            .frame(width: GuidanceArrowStyle.lineWidth, height: length - GuidanceArrowStyle.arrowHeadLength)

                        // Flow stroke loading dari bawah ke atas
                        GeometryReader { barProxy in
                            let totalH = barProxy.size.height
                            let headY = totalH * (1.0 - strokeHead)
                            let tailY = totalH * (1.0 - strokeTail)
                            let activeH = max(0, tailY - headY)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [color.opacity(0.2), color],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(width: GuidanceArrowStyle.lineWidth + 0.8, height: activeH)
                                .position(x: barProxy.size.width / 2, y: headY + activeH / 2)
                                .shadow(color: color.opacity(0.6), radius: 4)
                        }
                        .frame(width: GuidanceArrowStyle.lineWidth + 2, height: length - GuidanceArrowStyle.arrowHeadLength)
                    }
                } else {
                    // Panah mengarah ke bawah: Batang di atas, kepala di bawah
                    ZStack(alignment: .top) {
                        // Jalur track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(GuidanceArrowStyle.trackOpacity))
                            .frame(width: GuidanceArrowStyle.lineWidth, height: length - GuidanceArrowStyle.arrowHeadLength)

                        // Flow stroke loading dari atas ke bawah
                        GeometryReader { barProxy in
                            let totalH = barProxy.size.height
                            let headY = totalH * strokeHead
                            let tailY = totalH * strokeTail
                            let activeH = max(0, headY - tailY)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: [color.opacity(0.2), color],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .frame(width: GuidanceArrowStyle.lineWidth + 0.8, height: activeH)
                                .position(x: barProxy.size.width / 2, y: tailY + activeH / 2)
                                .shadow(color: color.opacity(0.6), radius: 4)
                        }
                        .frame(width: GuidanceArrowStyle.lineWidth + 2, height: length - GuidanceArrowStyle.arrowHeadLength)
                    }

                    ArrowHeadPolygon()
                        .fill(color.opacity(tipBrightness))
                        .frame(width: GuidanceArrowStyle.arrowHeadLength, height: GuidanceArrowStyle.arrowHeadWidth)
                        .rotationEffect(.degrees(90))
                        .scaleEffect(0.92 + 0.14 * tipBrightness)
                        .shadow(color: color.opacity(tipBrightness * 0.7), radius: 3)
                }
            }
            .frame(width: width, height: length)
        }
    }
}
