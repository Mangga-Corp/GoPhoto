import SwiftUI

/// Debug overlay: what the AI learned from the selected preset and the live values the
/// guide compares against it. Toggled with the ladybug button on the camera's top bar.
struct GuideDebugPanel: View {
    @Bindable var viewModel: CameraViewModel
    var onShowDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Picker("Guide mode", selection: $viewModel.guideMode) {
                ForEach(GuideMode.visible) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .tint(.yellow)
            .font(.caption.weight(.semibold))
            if !viewModel.guideMode.steps.isEmpty {
                Toggle("Keep finished steps", isOn: $viewModel.latchSteps)
                    .font(.caption2.weight(.semibold))
                    .tint(.yellow)
                    .fixedSize()
            }
            Text(presetLine).fontWeight(.semibold)
            Text(angleLine)
            if let timing = viewModel.lastShotTiming { Text("Last shot: " + timing) }
            if let cut = cutLine { Text(cut) }
            Text(targetLine).fontWeight(.semibold).foregroundStyle(.yellow)
            Text(phoneLine)
            Text(String(format: "Horizon roll %+.1f°", viewModel.roll))
            Text(frameLine)
            Text(personLine)
            Text(exposureLine)
            Text(sunLine)
            Text(lightingLine)
            if let failure = viewModel.lighting.weatherFailure {
                Text("Weather error: \(failure)").foregroundStyle(.red).lineLimit(4)
            }
            if viewModel.guideMode.crops, let w = viewModel.evaluation.cropWindow {
                Text(String(format: "Crop %.0f%% of frame (min %.0f%%) · x%.2f y%.2f",
                            w.width * 100, (viewModel.evaluation.cropMinScale ?? 0) * 100, w.minX, w.minY))
            }
            if viewModel.guideMode == .fixedRules || viewModel.guideMode == .wideCrop {
                Text("Rules: framing \(viewModel.evaluation.framingRule ?? "size ±30%") · height \(viewModel.evaluation.heightRule ?? "none")")
            }
            if !viewModel.guideMode.steps.isEmpty {
                Text(viewModel.isPhoneStill
                     ? "Measuring: still · \(viewModel.snapshotFrames) frames"
                     : "Measuring: phone moving · values frozen")
                Text(distanceLine)
                Text(heightLine)
                Text(stepsLine)
            }
            Text("Instruction: \(String(describing: viewModel.instruction))")
            Button("Analysis details", action: onShowDetails)
                .font(.caption2.weight(.semibold))
                .padding(.top, 2)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Lines

    private var presetLine: String {
        let name = viewModel.presetName ?? "No preset"
        if viewModel.isAnalyzingPreset { return "\(name) · analyzing…" }
        guard let analysis = viewModel.analysis else { return "\(name) · not analyzed" }
        return "\(name) · \(analysis.photoCount) photos, person in \(analysis.subjectPhotoCount)"
    }

    /// Where the preset's half-body photos cut the body (from the skeleton).
    private var cutLine: String? {
        guard let analysis = viewModel.analysis, let level = analysis.cutLevel else { return nil }
        var line = "Half-body cut: \(level)"
        if let n = analysis.cutLevelCount, let of = analysis.cutLevelOf { line += " (\(n)/\(of) photos)" }
        if let below = analysis.cutBelowHip { line += String(format: " · %.1f torso below hips", below) }
        return line
    }

    private var angleLine: String {
        guard let analysis = viewModel.analysis else { return "Angle: —" }
        let order: [CameraAngleCategory] = [.wormsEye, .lowAngle, .eyeLevel, .highAngle, .birdsEye]
        let counts = order.compactMap { category -> String? in
            guard let n = analysis.angleCounts?[category.rawValue], n > 0 else { return nil }
            return "\(category.label) \(n)"
        }
        var detail: [String] = []
        if let read = analysis.angleDeterminedCount { detail.append("\(read)/\(analysis.photoCount) read") }
        if let share = analysis.angleLeadingShare, share > 0 { detail.append(String(format: "lead %.0f%%", share * 100)) }
        let list = counts.isEmpty ? "none read" : counts.joined(separator: ", ")
        return "Angle: \(list)" + (detail.isEmpty ? "" : " (\(detail.joined(separator: ", ")))")
    }

    private var targetLine: String {
        let tolerance = String(format: "±%.0f°", GuideFlow.tiltEnter)
        switch viewModel.analysis?.angle {
        case .match(let category, let pitchDown):
            let label = PresetAnalysis.EyeSide(rawValue: category).map { $0 == .above ? "above eyes" : "below eyes" }
                ?? CameraAngleCategory(rawValue: category)?.label ?? category
            var line = "Target: \(label)"
            if let analysis = viewModel.analysis, let source = analysis.eyeSideSource {
                var why = [source]
                if let share = analysis.eyeAboveShare { why.append(String(format: "above %.0f%%", share * 100)) }
                if let n = analysis.eyeSidePhotoCount { why.append("\(n) photos") }
                if let framing = analysis.shotSize ?? analysis.framing { why.append(framing) }
                line += " (\(why.joined(separator: ", ")))"
            }
            return line + " · tilt \(Self.tilt(pitchDown)) \(tolerance)"
        case .noGuidance:
            return "Target: no angle guidance (no majority)"
        case .fixedRule:
            return "Target: fixed rule (no angle read) · tilt 0° \(tolerance)"
        case nil:
            return "Target: fixed rule (not analyzed) · tilt 0° \(tolerance)"
        }
    }

    private var phoneLine: String {
        var line = "Phone tilt \(Self.tilt(viewModel.pitch))"
        if let error = viewModel.pitchError { line += String(format: " · diff %+.1f°", error) }
        return line
    }

    private var frameLine: String {
        let r = viewModel.target.rect
        return String(format: "Frame target x%.2f y%.2f w%.2f h%.2f", r.minX, r.minY, r.width, r.height)
    }

    private var personLine: String {
        guard let box = viewModel.personBox else { return "Person: not found" }
        let o = viewModel.target.offset(of: box)
        return String(format: "Person dx %+.2f dy %+.2f size ×%.2f", o.dx, o.dy, o.sizeRatio)
    }

    private var exposureLine: String {
        guard let e = viewModel.exposure else { return "Exposure: —" }
        let shutter = e.shutter > 0 ? "1/\(Int((1 / e.shutter).rounded()))" : "—"
        return String(format: "Person lift %+.2f EV · ISO %.0f · ", e.lift, e.iso) + shutter + " s"
            + (e.isBacklit ? " · backlit" : "")
    }

    private var sunLine: String {
        let lighting = viewModel.lighting
        guard let sun = lighting.sunPosition else { return "Sun: — (no location)" }
        let heading = lighting.heading.map { String(format: "%.0f°", $0.degrees) + ($0.isReliable ? "" : "?") } ?? "—"
        return String(format: "Sun az %.0f° alt %.0f°", sun.azimuth, sun.altitude) + " · camera \(heading)"
    }

    private var lightingLine: String {
        let lighting = viewModel.lighting
        let weather = lighting.weather.map { String(describing: $0) } ?? "unknown"
        guard let advice = lighting.recommendation else { return "Light: weather \(weather) · no advice" }
        let rule = advice.rule
        return "Light: \(advice.scene.rawValue) (weather \(weather)) · f/\(rule.aperture.lowerBound.formatted())–"
            + "\(rule.aperture.upperBound.formatted()) info · shutter ≥1/\(Int((1 / advice.slowestShutter).rounded()))"
            + " · ISO \(rule.iso.lowerBound)–\(rule.iso.upperBound) info"
    }

    private var distanceLine: String {
        let e = viewModel.evaluation
        var line = "Distance from \(e.distanceSource)"
        if let r = e.sizeRatio { line += String(format: " · size ×%.2f", r) }
        if let h = e.headAngle {
            line += String(format: " · head %.1f°", h)
            if let t = viewModel.analysis?.headAngle { line += String(format: " / %.1f°", t) }
        }
        return line
    }

    private var heightLine: String {
        let e = viewModel.evaluation
        func words(_ v: Double) -> String { String(format: "%.1f° %@", abs(v), v >= 0 ? "above" : "below") }
        let now = e.eyeElevation.map(words) ?? "—"
        let target = e.eyeElevationTarget.map(words) ?? "none"
        let capped = e.heightCapped ? " (capped to reach)" : ""
        let distance = e.distanceMeters.map { String(format: " · ~%.1f m", $0) } ?? ""
        return "Camera vs eyes \(now) · target \(target)\(capped)\(distance)"
    }

    private var stepsLine: String {
        viewModel.guideMode.steps.map { step -> String in
            switch viewModel.evaluation.checks[step] {
            case .ok: return "\(step.title) " + (viewModel.evaluation.latched.contains(step) ? "✓🔒" : "✓")
            case .pending: return "\(step.title) •"
            case .skipped(let why): return "\(step.title) – (\(why))"
            case .locked: return "\(step.title) …"
            case nil: return "\(step.title) ?"
            }
        }.joined(separator: "  ")
    }

    /// Pitch in the `DeviceTilt` convention (+ = down) as words.
    private static func tilt(_ pitchDown: Double) -> String {
        String(format: "%.1f° %@", abs(pitchDown), pitchDown >= 0 ? "down" : "up")
    }
}
