//
//  SceneIdeasViews.swift
//  gophoto
//
//  Scene Ideas on the camera: the AI button (right of the shutter) reads the live view, asks
//  Foundation Models for place ideas, and shows them in a sheet. "Use this idea" puts a small
//  place guide under the preview. Without a scan the camera works as before.
//

import SwiftUI
import UIKit
import Observation

// MARK: - State

@MainActor @Observable final class SceneIdeasModel {
    enum Phase: Equatable {
        case idle, reading, thinking
        case blocked(SceneInputCheck.Status)
        case done(SceneIdeasResult)
        case failed(String)
    }
    var phase: Phase = .idle
    /// The view that was scanned (shown at the top of the sheet).
    var frame: CGImage?
    /// The idea whose place guide is shown on the camera.
    var chosen: SceneIdea?
    var skipped: Set<Int> = []
    /// Bumped on every new scan: the image sweep plays once per scan, not on "More ideas".
    var scanID = 0
    var isBusy: Bool { phase == .reading || phase == .thinking }

    /// InputCheck first (no model call); a blurry or dark view gets a soft block with "Find ideas anyway".
    func scan(_ image: CGImage?) async {
        skipped = []
        if let reason = SceneIdeaAdvisor.unavailableReason { phase = .failed(reason); return }
        guard let image else { phase = .failed("Couldn't read the camera view. Try again."); return }
        frame = image
        scanID += 1
        if let data = SceneInputCheck.jpeg(image), let f = SceneInputCheck.features(data) {
            let status = SceneInputCheck.status(f)
            if status != .ok { phase = .blocked(status); return }
        }
        await analyze()
    }

    /// Ask the model (again) for the scanned view.
    func analyze() async {
        guard let frame, phase != .thinking else { return }
        phase = .thinking
        skipped = []
        do { phase = .done(try await SceneIdeaAdvisor.run(frame)) }
        catch { phase = .failed(SceneIdeaAdvisor.describe(error)) }
    }
}

// MARK: - Camera button (Apple Intelligence symbol)

struct SceneIdeasButton: View {
    let isBusy: Bool
    /// A place guide is on the camera: the button turns yellow until the guide is closed.
    var isActive = false
    let action: () -> Void
    private let size: CGFloat = 52
    private static let symbol = UIImage(systemName: "apple.intelligence") != nil ? "apple.intelligence" : "sparkles"

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: Self.symbol)
                        .font(.title2)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isActive ? .yellow : .white)
                }
            }
            .frame(width: size, height: size)
            .background(isActive ? Color.yellow.opacity(0.22) : Color.white.opacity(0.15), in: Circle())
            .overlay(Circle().stroke(isActive ? Color.yellow : .clear, lineWidth: 1.5))
            .animation(.snappy, value: isActive)
        }
        .disabled(isBusy)
        .accessibilityLabel("Photo ideas for this place")
        .accessibilityValue(isActive ? "Place guide on" : "")
    }
}

// MARK: - Sheet

struct SceneIdeasSheet: View {
    @Bindable var model: SceneIdeasModel
    var onUse: (SceneIdea) -> Void
    var onRescan: () -> Void
    @Environment(\.dismiss) private var dismiss
    /// How many idea cards are filled in (one by one after the result arrives).
    @State private var revealed = 0
    /// The tapped card: it opens the staging preview and its Skip / Use this idea buttons.
    @State private var selectedID: Int?

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    // Scanned view stays on top (not scrolled away) so choosing a card visibly
                    // stages that idea on it. Capped at ~45% of the sheet height.
                    if let frame = model.frame {
                        scannedImage(frame)
                            .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.45)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                            .transition(.opacity)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) { content }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                    }
                }
            }
            .onChange(of: model.phase) { _, phase in
                guard case .done(let r) = phase else { revealed = 0; return }
                revealed = 0
                selectedID = nil
                Task {
                    for k in 1...max(r.ideas.count, 1) {
                        try? await Task.sleep(for: .milliseconds(k == 1 ? 150 : 450))
                        withAnimation(.spring(duration: 0.4)) { revealed = k }
                    }
                }
            }
            .onAppear { if case .done = model.phase { revealed = 99 } }
            .navigationTitle("Photo ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    /// The idea whose staging is drawn on the scanned image (the selected card).
    private var selectedIdea: SceneIdea? {
        guard let selectedID, case .done(let r) = model.phase else { return nil }
        return r.ideas.first { $0.id == selectedID }
    }

    /// Top image: plain scan, or the selected idea's person outline + element box on it.
    private func scannedImage(_ frame: CGImage) -> some View {
        Image(decorative: frame, scale: 1)
            .resizable().scaledToFit()
            .overlay {
                if let idea = selectedIdea {
                    SceneStagingOverlay(idea: idea)
                        .id(idea.id)                                  // crossfade when switching cards
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .animation(.snappy, value: selectedID)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(selectedIdea.map {
                "Scanned view with example staging: person outline and where the \(ScenePersonGuide.name($0.element)) goes"
            } ?? "Scanned view")
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle, .reading:
            waiting("Reading the view…")
        case .thinking:
            waiting("Looking at the place…")
        case .blocked(let status):
            VStack(alignment: .leading, spacing: 10) {
                Label(SceneInputCheck.message(status), systemImage: status == .tooDark ? "moon.fill" : "camera.metering.unknown")
                    .foregroundStyle(.orange)
                HStack {
                    Button("Scan again") { onRescan() }.buttonStyle(.borderedProminent)
                    Button("Find ideas anyway") { Task { await model.analyze() } }.buttonStyle(.bordered)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message).foregroundStyle(.secondary)
                Button("Scan again") { onRescan() }.buttonStyle(.borderedProminent)
            }
        case .done(let result):
            results(result)
        }
    }

    /// Placeholder cards while the model works, so the wait feels shorter.
    private func waiting(_ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(caption, systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary)
            SkeletonIdeaCard()
            SkeletonIdeaCard()
        }
    }

    @ViewBuilder private func results(_ r: SceneIdeasResult) -> some View {
        let visible = r.ideas.filter { !model.skipped.contains($0.id) }
        if r.ideas.isEmpty {
            Text("No strong idea from this angle.").font(.headline)
            Text("Turn a little or step back, then scan again.").font(.subheadline).foregroundStyle(.secondary)
        } else if visible.isEmpty {
            Text("All ideas skipped.").font(.headline)
        }
        ForEach(Array(visible.enumerated()), id: \.element.id) { k, idea in
            card(idea)
                .opacity(k < revealed ? 1 : 0)
                .offset(y: k < revealed ? 0 : 12)
                .overlay { if k >= revealed { SkeletonIdeaCard() } }
        }
        if !r.warnings.isEmpty {
            Label("Avoid: " + r.warnings.joined(separator: ", "), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
        }
        HStack {
            Button("More ideas") { Task { await model.analyze() } }.buttonStyle(.bordered)
            Button("Scan again") { onRescan() }.buttonStyle(.bordered)
        }
        Text("Ideas are suggestions, not rules. Skip what doesn't fit.")
            .font(.caption2).foregroundStyle(.secondary)
    }

    private func card(_ i: SceneIdea) -> some View {
        let isSelected = selectedID == i.id
        return VStack(alignment: .leading, spacing: 10) {
            // Whole summary is one button: tap to open / close this idea.
            Button {
                withAnimation(.snappy) { selectedID = isSelected ? nil : i.id }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(SceneText.roleTitle(i.role), systemImage: SceneText.roleIcon(i.role))
                            .font(.caption.bold()).foregroundStyle(.tint)
                        Spacer()
                        Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(i.element).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                    Text(i.why).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    Text(i.keep).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isSelected ? "Hides the staging preview" : "Shows how to stage this photo")

            if isSelected {
                staging(i)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(isSelected ? 0.18 : 0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// How to stage it (the outline is drawn on the top image), then the two actions.
    @ViewBuilder private func staging(_ i: SceneIdea) -> some View {
        let g = ScenePersonGuide.lines(i)
        Text("Staging shown on the photo above. It's an example placement; pick the side that fits.")
            .font(.caption2).foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 6) {
            Label(g.person, systemImage: "figure.stand").font(.footnote)
            Label(g.photographer, systemImage: "camera").font(.footnote)
            Label(ScenePersonGuide.safety, systemImage: "exclamationmark.shield").font(.caption).foregroundStyle(.orange)
        }
        .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    selectedID = nil
                    _ = model.skipped.insert(i.id)
                }
            } label: {
                Text("Skip").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            Button { onUse(i) } label: {
                Text("Use this idea").bold().frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Place guide on the camera (after "Use this idea")

struct PlaceGuideCard: View {
    let idea: SceneIdea
    var onClose: () -> Void
    @State private var isExpanded = false

    var body: some View {
        let g = ScenePersonGuide.lines(idea)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label(SceneText.roleTitle(idea.role) + " · " + ScenePersonGuide.name(idea.element),
                      systemImage: SceneText.roleIcon(idea.role))
                    .font(.footnote.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button { withAnimation(.snappy) { isExpanded.toggle() } } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up").frame(width: 44, height: 44)
                }
                .accessibilityLabel(isExpanded ? "Show less" : "Show full guide")
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel("Close place guide")
            }
            if isExpanded {
                Text("Person: " + g.person).font(.caption)
                Text("Photographer: " + g.photographer).font(.caption)
                Text(ScenePersonGuide.safety).font(.caption2).foregroundStyle(.orange)
            } else {
                Text(g.photographer).font(.caption).lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - One Apple Intelligence-style sweep over the camera preview (DIY, not an Apple API)

/// Covers the preview with the scanned (frozen) frame and plays one colour sweep from bottom to
/// top plus a fading edge glow. `SceneScanSweep.duration` is how long the caller waits before
/// opening the ideas sheet.
struct SceneScanSweep: View {
    static let duration: Double = 1.5
    let frame: CGImage?
    @State private var sweep: CGFloat = 0        // 0 = band below the image, 1 = above it
    @State private var glow: Double = 1          // edge glow, fades after the sweep
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let palette: [Color] = [
        Color(red: 0.55, green: 0.62, blue: 1.00),   // blue
        Color(red: 0.74, green: 0.51, blue: 0.95),   // purple
        Color(red: 0.96, green: 0.73, blue: 0.92),   // pink
        Color(red: 1.00, green: 0.40, blue: 0.47),   // red
        Color(red: 1.00, green: 0.73, blue: 0.44),   // orange
        Color(red: 0.55, green: 0.62, blue: 1.00),
    ]

    var body: some View {
        ZStack {
            if let frame {
                Image(decorative: frame, scale: 1).resizable().scaledToFill()
            } else {
                Color.black
            }
        }
            .overlay {
                GeometryReader { geo in
                    let h = geo.size.height
                    ZStack {
                        if !reduceMotion {
                            LinearGradient(colors: [.clear, Self.palette[0], Self.palette[1], Self.palette[2], Self.palette[4], .clear],
                                           startPoint: .bottom, endPoint: .top)
                                .frame(height: h * 0.5)
                                .blur(radius: 24)
                                .opacity(0.8)
                                .blendMode(.plusLighter)
                                .offset(y: h * 0.75 - sweep * h * 1.5)
                        }
                        Rectangle()
                            .strokeBorder(AngularGradient(colors: Self.palette, center: .center), lineWidth: 8)
                            .blur(radius: 8)
                            .blendMode(.plusLighter)
                            .opacity(glow)
                    }
                    .frame(width: geo.size.width, height: h)
                }
            }
            .clipped()
            .onAppear {
                guard !reduceMotion else { withAnimation(.easeOut(duration: 1.2)) { glow = 0 }; return }
                withAnimation(.easeInOut(duration: 1.4)) { sweep = 1 }
                withAnimation(.easeOut(duration: 0.5).delay(1.0)) { glow = 0 }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityLabel("Scanning the view")
    }
}

// MARK: - Skeleton card (placeholder while waiting)

struct SkeletonIdeaCard: View {
    @State private var shimmer = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            bar(width: 90, height: 10)
            bar(width: 180, height: 14)
            bar(width: nil, height: 12)
            bar(width: 220, height: 10)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .opacity(shimmer ? 0.55 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { shimmer = true } }
        .accessibilityHidden(true)
    }
    private func bar(width: CGFloat?, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color.secondary.opacity(0.25))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .frame(width: width, height: height)
    }
}

// MARK: - Staging preview (person outline + where the element goes; same layout as the prototype guide)

/// Fixed layout per role, as fractions of the frame. The model doesn't know where the element is
/// in the picture, so this is an example placement the photographer matches on screen.
struct SceneStagingOverlay: View {
    let idea: SceneIdea
    var flipped = false

    private struct Spec {
        var personX: CGFloat, feetY: CGFloat, personH: CGFloat, half = false
        var label: String, box: CGRect
        var line: (CGPoint, CGPoint)? = nil
        var edges = false
    }

    private var spec: Spec {
        let x = ScenePersonGuide.name(idea.element)
        switch idea.role {
        case "leadingLine" where ScenePersonGuide.isOverhead(idea.element):
            return Spec(personX: 0.5, feetY: 0.93, personH: 0.40, label: x, box: CGRect(x: 0.08, y: 0.04, width: 0.84, height: 0.30))
        case "leadingLine":
            return Spec(personX: 0.55, feetY: 0.62, personH: 0.30, label: x + " starts here",
                        box: CGRect(x: 0.03, y: 0.84, width: 0.50, height: 0.11),
                        line: (CGPoint(x: 0.06, y: 1.0), CGPoint(x: 0.53, y: 0.63)))
        case "landmark":
            return Spec(personX: 0.72, feetY: 0.90, personH: 0.52, label: x, box: CGRect(x: 0.05, y: 0.10, width: 0.50, height: 0.48))
        case "frame":
            return Spec(personX: 0.5, feetY: 0.80, personH: 0.42, label: x + " on the edges",
                        box: CGRect(x: 0.20, y: 0.02, width: 0.60, height: 0.08), edges: true)
        case "plainBackdrop":
            return Spec(personX: 0.5, feetY: 1.02, personH: 0.58, half: true, label: "only " + x + " behind the head",
                        box: CGRect(x: 0.12, y: 0.06, width: 0.76, height: 0.30))
        case "pattern":
            return Spec(personX: 0.70, feetY: 0.90, personH: 0.50, label: x + " fills the background",
                        box: CGRect(x: 0.04, y: 0.08, width: 0.52, height: 0.56))
        default:
            return Spec(personX: 0.72, feetY: 0.90, personH: 0.50, label: x, box: CGRect(x: 0.05, y: 0.08, width: 0.46, height: 0.34))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let sp = spec
            let fx: (CGFloat) -> CGFloat = { flipped ? 1 - $0 : $0 }
            ZStack(alignment: .topLeading) {
                Path { p in
                    for f in [1.0 / 3, 2.0 / 3] {
                        p.move(to: CGPoint(x: w * f, y: 0)); p.addLine(to: CGPoint(x: w * f, y: h))
                        p.move(to: CGPoint(x: 0, y: h * f)); p.addLine(to: CGPoint(x: w, y: h * f))
                    }
                }
                .stroke(.white.opacity(0.35), lineWidth: 1)
                if sp.edges {
                    Rectangle().strokeBorder(Color.yellow.opacity(0.5), lineWidth: min(w, h) * 0.10)
                }
                if let ln = sp.line {
                    Path { p in
                        p.move(to: CGPoint(x: fx(ln.0.x) * w, y: ln.0.y * h))
                        p.addLine(to: CGPoint(x: fx(ln.1.x) * w, y: ln.1.y * h))
                    }
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                }
                let bx = flipped ? 1 - sp.box.maxX : sp.box.minX
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .background(Color.yellow.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .topLeading) {
                        Text(sp.label).font(.caption2.bold()).foregroundStyle(.black).lineLimit(2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 5)).padding(4)
                    }
                    .frame(width: sp.box.width * w, height: sp.box.height * h)
                    .offset(x: bx * w, y: sp.box.minY * h)
                let ph = sp.personH * h
                let pw = ph * (sp.half ? 0.95 : 0.32)
                SceneSilhouette(half: sp.half)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .frame(width: pw, height: ph)
                    .offset(x: fx(sp.personX) * w - pw / 2, y: sp.feetY * h - ph)
            }
            .frame(width: w, height: h, alignment: .topLeading)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Simple person outline: head + body (+ legs for a full-body shot).
nonisolated struct SceneSilhouette: Shape {
    var half = false
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        let head = half ? w * 0.36 : w * 0.34
        p.addEllipse(in: CGRect(x: r.midX - head / 2, y: r.minY, width: head, height: head * 1.15))
        let top = r.minY + head * 1.25
        if half {
            p.addRoundedRect(in: CGRect(x: r.minX, y: top, width: w, height: r.maxY - top),
                             cornerSize: CGSize(width: w * 0.3, height: w * 0.3))
        } else {
            let torso = h * 0.40
            p.addRoundedRect(in: CGRect(x: r.minX + w * 0.08, y: top, width: w * 0.84, height: torso),
                             cornerSize: CGSize(width: w * 0.25, height: w * 0.25))
            let legTop = top + torso - w * 0.12
            let legW = w * 0.32
            for x in [r.midX - legW - w * 0.03, r.midX + w * 0.03] {
                p.addRoundedRect(in: CGRect(x: x, y: legTop, width: legW, height: r.maxY - legTop),
                                 cornerSize: CGSize(width: legW / 2, height: legW / 2))
            }
        }
        return p
    }
}
