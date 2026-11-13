//
//  ShotAnalysisScreen.swift
//  gophoto
//
//  Developer mode: what the analysis learned for ONE shot size (full / three-quarter / half /
//  one-quarter / sitting), picked at the top. Every value here is what the camera guides with
//  when that shot size is picked above the shutter.
//
import SwiftUI

struct ShotAnalysisScreen: View {
    let analysis: PresetAnalysis?
    let photos: [PhotoItem]
    let presetName: String
    @State var selection: Option

    enum Option: Hashable, Identifiable {
        case shot(PresetAnalysis.ShotSize)
        case sitting
        var id: String { title }
        var title: String {
            switch self {
            case .shot(let s): s.title
            case .sitting: "Sitting"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss

    init(analysis: PresetAnalysis?, photos: [PhotoItem], presetName: String, initial: PresetAnalysis.ShotSize?) {
        self.analysis = analysis
        self.photos = photos
        self.presetName = presetName
        let first = initial.map(Option.shot) ?? analysis?.availableShots.first.map(Option.shot) ?? .sitting
        _selection = State(initialValue: first)
    }

    private var options: [Option] {
        var list = (analysis?.availableShots ?? []).map(Option.shot)
        if analysis?.sittingVariant != nil { list.append(.sitting) }
        return list
    }

    private var variant: PresetAnalysis? {
        switch selection {
        case .shot(let s): analysis?.shotVariant(s)
        case .sitting: analysis?.sittingVariant
        }
    }

    /// The preset's photos in this shot size (standing), or the seated ones.
    private var variantPhotos: [PhotoItem] {
        photos.filter { photo in
            let key = photo.id.uuidString
            let sitting = analysis?.photoPostures?[key] == BodyPosture.sitting.rawValue
            switch selection {
            case .shot(let s): return analysis?.photoShotSizes?[key] == s.rawValue && !sitting
            case .sitting: return sitting
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if options.isEmpty {
                    Text("No analysis for this preset yet.").foregroundStyle(.secondary)
                } else {
                    Section {
                        Picker("Shot size", selection: $selection) {
                            ForEach(options) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let v = variant {
                        photosSection
                        heightSection(v)
                        tiltSection(v)
                        framingSection(v)
                        blurSection(v)
                        Section("Analysis") {
                            row("Version", "\(v.version)\(v.isCurrent ? "" : " (old, re-analysing)")")
                            row("Photos", "\(v.photoCount) · person read in \(v.subjectPhotoCount)")
                        }
                    }
                }
            }
            .navigationTitle(presetName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // MARK: Sections

    private var photosSection: some View {
        Section("Photos (\(variantPhotos.count))") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(variantPhotos, id: \.id) { photo in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 86)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityLabel("Reference photo")
                    }
                }
            }
        }
    }

    private func heightSection(_ v: PresetAnalysis) -> some View {
        Section("Camera height") {
            if let anchor = v.anchorReference {
                row("Anchor vote", "\(anchor): \(v.anchorAbove ?? 0) above · \(v.anchorBelow ?? 0) below")
                if let styles = v.anchorStyleCount {
                    row("Styles", styles > 1 ? "\(styles) · biggest used (\(v.anchorTargetPhotoCount ?? 0) photos)"
                                             : "1 · \(v.anchorTargetPhotoCount ?? 0) photos used")
                }
            } else {
                row("Anchor vote", "not used (eye-line vote)")
            }
            row("Side of the eyes", [v.eyeSide, v.eyeSideSource].compactMap { $0 }.joined(separator: " · ").ifEmpty("—"))
            if let faces = v.eyeOffsetFaces {
                row("Target (faces)", String(format: "%+.2f face ≈ %+.0f cm %@", faces,
                                             faces * GuideFlow.faceHeightMeters * 100, faces >= 0 ? "above eyes" : "below eyes"))
            }
            row("Vantage range", Self.vantageText(v.vantageRange))
            if let e = v.eyeElevation { row("Target (angle)", String(format: "%+.1f°", e)) }
            if let w = v.eyeElevationWeighted { row("Weighted 1/σ²", String(format: "%+.1f°", w)) }
        }
    }

    private func tiltSection(_ v: PresetAnalysis) -> some View {
        Section("Tilt") {
            switch v.angle {
            case .match(let category, let pitchDown):
                row("Target", String(format: "%.1f° %@ (%@)", abs(pitchDown), pitchDown >= 0 ? "down" : "up", category))
            case .noGuidance:
                row("Target", "no guidance (no majority)")
            case .fixedRule:
                row("Target", "fixed rule: phone straight")
            }
        }
    }

    private func framingSection(_ v: PresetAnalysis) -> some View {
        Section("Framing") {
            if let b = v.subjectBox {
                row("Person box", String(format: "x %.2f y %.2f · w %.2f h %.2f", b.minX, b.minY, b.width, b.height))
            }
            row("Cut off", [v.clippedTop == true ? "top" : nil, v.clippedBottom == true ? "bottom" : nil]
                .compactMap { $0 }.joined(separator: " + ").ifEmpty("none"))
            if let f = v.faceHeight { row("Face height", String(format: "%.0f%% of frame", f * 100)) }
            if let h = v.headAngle { row("Head angle", String(format: "%.1f°", h)) }
            if let b = v.bodyAngle { row("Body angle", String(format: "%.1f°", b)) }
            if let cut = v.cutLevel { row("Cut level", cut) }
            if case .shot(let s) = selection { row("Body cut rule", Self.cutRule(s)) }
        }
    }

    private func blurSection(_ v: PresetAnalysis) -> some View {
        Section("Background blur") {
            if let r = v.backgroundBlur {
                let look = r >= BokehProcessor.sharpReferenceRatio ? "sharp → no blur copy"
                    : r >= 0.6 ? "light blur" : r >= 0.35 ? "medium blur" : "strong blur"
                row("References", String(format: "%.2f (%d photos) · %@", r, v.backgroundBlurCount ?? 0, look))
            } else {
                row("References", "not measured → 1/3 strength")
            }
        }
    }

    // MARK: Helpers

    /// Display only (12 Nov, step 1): range in face heights, kind, confidence, median σ, photos.
    private static func vantageText(_ r: PresetAnalysis.VantageRange?) -> String {
        guard let r else { return "— (rescan)" }
        let span: String
        if let g = r.groups {
            span = g.map { String(format: "[%+.1f…%+.1f]", $0[0], $0[1]) }.joined(separator: " | ")
        } else if let lo = r.low, let hi = r.high {
            span = String(format: "[%+.1f…%+.1f]", lo, hi)
        } else {
            span = "—"
        }
        return String(format: "%@ · %@ · %@ · σ̃ %.1f · %d photos (+%d dropped)", span, r.kind, r.confidence,
                      r.medianSigma, r.used, r.excluded)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private static func cutRule(_ shot: PresetAnalysis.ShotSize) -> String {
        switch shot {
        case .full: "feet in frame"
        case .threeQuarter: "hips in, feet out"
        case .half: "knees out"
        case .quarter: "hips out"
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
