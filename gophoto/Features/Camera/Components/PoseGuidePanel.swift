//
//  PoseGuidePanel.swift
//  gophoto
//
//  Optional side-view pose guide (bottom right of the camera), from the "Panduan pose foto bukti"
//  design: A = annotated scene with the photographer, the subject, height and angle labels;
//  B = live side view, the phone now against a dashed target phone. Toggled next to the ladybug.
//
//  Heights are relative to the subject's eyes (what the analysis measures). The drawing places
//  the eyes at `assumedEyeCm` only to have a floor to draw on; labels never show that number.
//

import SwiftUI

/// What the pose guide draws. Heights in cm relative to the subject's eyes (+ = phone above them),
/// tilt in degrees with + = phone tilted up (the design's convention; the guide uses + = down).
struct PoseGuideState: Equatable {
    var heightNow: Double?
    var heightTarget: Double?
    var tiltNow: Double
    var tiltTarget: Double?
    /// Camera to subject, metres (nil when not estimated yet).
    var distance: Double?
    var heightOK: Bool
    var tiltOK: Bool

    var isOK: Bool { heightOK && tiltOK }

    /// One line, height first (the guide's order), then tilt.
    var instruction: String {
        if isOK { return "Matched. Hold still and shoot." }
        if !heightOK, let now = heightNow, let target = heightTarget {
            let cm = Int(abs(target - now).rounded())
            return (target > now ? "Raise the phone " : "Lower the phone ") + "\(cm) cm"
        }
        if !tiltOK, let target = tiltTarget {
            let deg = Int(abs(target - tiltNow).rounded())
            return (target < tiltNow ? "Tilt down " : "Tilt up ") + "\(deg)°"
        }
        return heightTarget == nil && tiltTarget == nil ? "No angle target for this preset" : "Measuring…"
    }
}

enum PoseGuideStyle: String, CaseIterable {
    case off, annotated, sideView

    static let storageKey = "poseGuideStyle"

    var title: String {
        switch self {
        case .off: "Off"
        case .annotated: "A · Annotated scene"
        case .sideView: "B · Side view live"
        }
    }
}

struct PoseGuidePanel: View {
    let style: PoseGuideStyle
    let state: PoseGuideState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                switch style {
                case .annotated: AnnotatedPoseScene(state: state).aspectRatio(340 / 210, contentMode: .fit)
                case .sideView: SideViewPoseScene(state: state).aspectRatio(340 / 220, contentMode: .fit)
                case .off: EmptyView()
                }
            }
            .background(PoseColors.scene, in: RoundedRectangle(cornerRadius: 10))
            Text(state.instruction)
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.isOK ? PoseColors.ok : .white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 230)
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pose guide: \(state.instruction)")
    }
}

// MARK: - Drawing helpers (SVG view-box units, scaled to the canvas)

enum PoseColors {
    static let scene = Color(red: 0x26 / 255, green: 0x28 / 255, blue: 0x24 / 255)
    static let ink = Color(red: 0xD6 / 255, green: 0xD8 / 255, blue: 0xD1 / 255)
    static let dim = Color(red: 0x5E / 255, green: 0x62 / 255, blue: 0x5A / 255)
    static let mute = Color(red: 0x8B / 255, green: 0x8F / 255, blue: 0x86 / 255)
    static let ok = Color(red: 0x8F / 255, green: 0xC2 / 255, blue: 0x55 / 255)
    static let bad = Color(red: 0xF2 / 255, green: 0x93 / 255, blue: 0x8F / 255)
    static let phone = Color(red: 0xF1 / 255, green: 0xEF / 255, blue: 0xE8 / 255)
}

private enum PoseDraw {
    /// Where the subject's eyes sit in the drawing, cm above the ground (drawing only).
    static let assumedEyeCm = 150.0
    static let shoulderCm = 140.0, armCm = 60.0

    static func rad(_ d: Double) -> Double { d * .pi / 180 }

    /// Hand distance in front of the shoulder for a phone at `heightCm` (straight arm).
    static func handDx(_ heightCm: Double) -> Double {
        let dy = min(max(shoulderCm - heightCm, -armCm + 0.1), armCm - 0.1)
        return (armCm * armCm - dy * dy).squareRoot()
    }

    static func phone(_ ctx: GraphicsContext, at p: CGPoint, tilt: Double, scale: Double = 1,
                      fill: Color?, stroke: Color?, dashed: Bool) {
        var c = ctx
        c.translateBy(x: p.x, y: p.y)
        c.rotate(by: .degrees(-tilt))
        let w = 7 * scale, h = 20 * scale
        let rect = Path(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: 2)
        if let fill { c.fill(rect, with: .color(fill)) }
        if let stroke {
            c.stroke(rect, with: .color(stroke), style: StrokeStyle(lineWidth: 1, dash: dashed ? [2, 2] : []))
        }
    }

    /// The camera's line of sight to the ground (or `maxLength` when aimed level or up).
    static func ray(_ ctx: GraphicsContext, from p: CGPoint, tilt: Double, groundY: Double, maxLength: Double,
                    color: Color, width: Double, dashed: Bool) {
        var length = tilt < 0 ? (groundY - p.y) / sin(rad(-tilt)) : maxLength
        length = min(max(length, 0), maxLength)
        var path = Path()
        path.move(to: p)
        path.addLine(to: CGPoint(x: p.x + length * cos(rad(tilt)), y: p.y - length * sin(rad(tilt))))
        ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dashed ? [4, 4] : []))
    }

    static func line(_ ctx: GraphicsContext, _ a: CGPoint, _ b: CGPoint, _ color: Color, width: Double = 1,
                     dash: [CGFloat] = [], round: Bool = false) {
        var path = Path()
        path.move(to: a)
        path.addLine(to: b)
        ctx.stroke(path, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: round ? .round : .butt, dash: dash))
    }

    /// A stick person standing at `x` (view-box units) with the eyes at `eyeY`.
    static func person(_ ctx: GraphicsContext, x: Double, groundY: Double, eyeY: Double, color: Color) {
        let headR = 8.0
        let height = groundY - eyeY
        let hip = CGPoint(x: x, y: groundY - height * 0.55)
        ctx.stroke(Path(ellipseIn: CGRect(x: x - headR, y: eyeY - headR, width: headR * 2, height: headR * 2)),
                   with: .color(color), lineWidth: 2.5)
        line(ctx, CGPoint(x: x, y: eyeY + headR), hip, color, width: 3, round: true)
        line(ctx, hip, CGPoint(x: x - 10, y: groundY), color, width: 3, round: true)
        line(ctx, hip, CGPoint(x: x + 10, y: groundY), color, width: 3, round: true)
    }

    /// Text in screen points (not scaled with the drawing), at a view-box position.
    static func label(_ ctx: GraphicsContext, _ text: String, at p: CGPoint, scale: Double, color: Color,
                      anchor: UnitPoint = .leading) {
        ctx.draw(Text(text).font(.system(size: 10, weight: .semibold)).foregroundStyle(color),
                 at: CGPoint(x: p.x * scale, y: p.y * scale), anchor: anchor)
    }
}

// MARK: - A: annotated scene

private struct AnnotatedPoseScene: View {
    let state: PoseGuideState

    var body: some View {
        Canvas { context, size in
            let k = size.width / 340
            var ctx = context
            ctx.scaleBy(x: k, y: k)

            let s = 0.75, gy = 198.0, px = 62.0, W = 340.0
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: px + x * s, y: gy - y * s) }
            let eye = PoseDraw.assumedEyeCm
            let now = eye + (state.heightNow ?? 0)
            let target = state.heightTarget.map { eye + $0 }
            let distanceCm = min(max((state.distance ?? 2.3) * 100, 120), 330)

            PoseDraw.line(ctx, CGPoint(x: 0, y: gy), CGPoint(x: W, y: gy), PoseColors.mute, width: 1.5)

            // Subject and their eye line.
            let eyePoint = P(distanceCm, eye)
            PoseDraw.person(ctx, x: eyePoint.x, groundY: gy, eyeY: eyePoint.y, color: PoseColors.dim)
            PoseDraw.line(ctx, CGPoint(x: 8, y: eyePoint.y), eyePoint, PoseColors.mute, dash: [2, 3])

            // Photographer.
            let head = P(0, 160), neck = P(0, 151), hip = P(0, 85), shoulder = P(0, PoseDraw.shoulderCm)
            ctx.stroke(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)),
                       with: .color(PoseColors.ink), lineWidth: 2.5)
            PoseDraw.line(ctx, neck, hip, PoseColors.ink, width: 3, round: true)
            PoseDraw.line(ctx, hip, P(-12, 0), PoseColors.ink, width: 3, round: true)
            PoseDraw.line(ctx, hip, P(12, 0), PoseColors.ink, width: 3, round: true)

            // Target pose (dashed green).
            if let target {
                let q = P(PoseDraw.handDx(target), target)
                let tilt = state.tiltTarget ?? 0
                PoseDraw.line(ctx, shoulder, q, PoseColors.ok, width: 1.5, dash: [3, 3])
                PoseDraw.phone(ctx, at: q, tilt: tilt, fill: nil, stroke: PoseColors.ok, dashed: true)
                PoseDraw.ray(ctx, from: q, tilt: tilt, groundY: gy, maxLength: W,
                             color: PoseColors.ok, width: 1, dashed: true)
            }

            // Pose now.
            let q = P(PoseDraw.handDx(now), now)
            PoseDraw.line(ctx, shoulder, q, PoseColors.ink, width: 3, round: true)
            PoseDraw.ray(ctx, from: q, tilt: state.tiltNow, groundY: gy, maxLength: W,
                         color: state.isOK ? PoseColors.ok : PoseColors.bad, width: 1.5, dashed: false)
            PoseDraw.phone(ctx, at: q, tilt: state.tiltNow, fill: state.isOK ? PoseColors.ok : PoseColors.phone,
                           stroke: nil, dashed: false)

            // Height annotation: from the subject's eye line to the phone.
            let hc = state.heightOK ? PoseColors.ok : PoseColors.bad
            if let rel = state.heightNow {
                PoseDraw.line(ctx, CGPoint(x: 14, y: eyePoint.y), CGPoint(x: 14, y: q.y), hc)
                PoseDraw.line(ctx, CGPoint(x: 9, y: q.y), CGPoint(x: q.x - 6, y: q.y), hc, dash: [2, 2])
                let labelY = (eyePoint.y + q.y) / 2 - (abs(eyePoint.y - q.y) < 12 ? 8 : 0)
                PoseDraw.label(context, String(format: "%+.0f cm vs eyes", rel),
                               at: CGPoint(x: 18, y: labelY), scale: k, color: hc)
            }

            // Angle annotation.
            let tc = state.tiltOK ? PoseColors.ok : PoseColors.bad
            PoseDraw.line(ctx, q, CGPoint(x: q.x + 46, y: q.y), PoseColors.mute, dash: [2, 2])
            let a0 = min(0, -state.tiltNow), a1 = max(0, -state.tiltNow)
            if a1 - a0 > 1 {
                var arc = Path()
                for i in 0...16 {
                    let a = PoseDraw.rad(a0 + (a1 - a0) * Double(i) / 16)
                    let p = CGPoint(x: q.x + 32 * cos(a), y: q.y + 32 * sin(a))
                    if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
                }
                ctx.stroke(arc, with: .color(tc), lineWidth: 1.5)
            }
            PoseDraw.label(context, String(format: "%.0f°", state.tiltNow),
                           at: CGPoint(x: q.x + 50, y: q.y + (state.tiltNow < 0 ? 14 : -6)), scale: k, color: tc)
        }
    }
}

// MARK: - B: side view live

private struct SideViewPoseScene: View {
    let state: PoseGuideState

    var body: some View {
        Canvas { context, size in
            let k = size.width / 340
            var ctx = context
            ctx.scaleBy(x: k, y: k)

            let W = 340.0, gy = 206.0, s = 0.85, x = 70.0
            func Y(_ cm: Double) -> Double { gy - cm * s }
            let eye = PoseDraw.assumedEyeCm
            let now = eye + (state.heightNow ?? 0)

            PoseDraw.line(ctx, CGPoint(x: 0, y: gy), CGPoint(x: W, y: gy), PoseColors.mute, width: 1.5)
            // Subject and their eye line.
            PoseDraw.person(ctx, x: 285, groundY: gy, eyeY: Y(eye), color: PoseColors.dim)
            PoseDraw.line(ctx, CGPoint(x: 20, y: Y(eye)), CGPoint(x: 285, y: Y(eye)), PoseColors.mute, dash: [2, 3])

            // Target (dashed green ghost).
            if let target = state.heightTarget.map({ eye + $0 }) {
                let p = CGPoint(x: x, y: Y(target))
                let tilt = state.tiltTarget ?? 0
                PoseDraw.ray(ctx, from: p, tilt: tilt, groundY: gy, maxLength: 360,
                             color: PoseColors.ok, width: 1, dashed: true)
                PoseDraw.phone(ctx, at: p, tilt: tilt, scale: 1.5, fill: nil, stroke: PoseColors.ok, dashed: true)
            }

            // Height marker and the phone now.
            let p = CGPoint(x: x, y: Y(now))
            PoseDraw.line(ctx, CGPoint(x: 36, y: gy), CGPoint(x: 36, y: p.y), PoseColors.mute, dash: [2, 2])
            PoseDraw.ray(ctx, from: p, tilt: state.tiltNow, groundY: gy, maxLength: 360,
                         color: state.isOK ? PoseColors.ok : PoseColors.bad, width: 2, dashed: false)
            PoseDraw.phone(ctx, at: p, tilt: state.tiltNow, scale: 1.5,
                           fill: state.isOK ? PoseColors.ok : PoseColors.phone, stroke: nil, dashed: false)
            PoseDraw.label(context, "eyes", at: CGPoint(x: 250, y: Y(eye) - 8), scale: k,
                           color: PoseColors.mute, anchor: .trailing)
        }
    }
}

#Preview {
    VStack {
        PoseGuidePanel(style: .annotated,
                       state: PoseGuideState(heightNow: -40, heightTarget: -15, tiltNow: -12, tiltTarget: -30,
                                             distance: 2.3, heightOK: false, tiltOK: false))
        PoseGuidePanel(style: .sideView,
                       state: PoseGuideState(heightNow: -40, heightTarget: -15, tiltNow: -12, tiltTarget: -30,
                                             distance: 2.3, heightOK: false, tiltOK: false))
    }
    .padding()
    .background(.gray)
}
