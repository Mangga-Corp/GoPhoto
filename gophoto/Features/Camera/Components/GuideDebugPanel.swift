import SwiftUI

/// Debug overlay: what the AI learned from the selected preset and the live values the
/// guide compares against it. Toggled with the ladybug button on the camera's top bar.
struct GuideDebugPanel: View {
    let viewModel: CameraViewModel
    var onShowDetails: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presetLine).fontWeight(.semibold)
            Text(angleLine)
            Text(targetLine).fontWeight(.semibold).foregroundStyle(.yellow)
            Text(phoneLine)
            Text(String(format: "Horizon roll %+.1f°", viewModel.roll))
            Text(frameLine)
            Text(personLine)
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
        let tolerance = String(format: "±%.0f°", GuideInstruction.angleEnter)
        switch viewModel.analysis?.angle {
        case .match(let category, let pitchDown):
            let label = CameraAngleCategory(rawValue: category)?.label ?? category
            return "Target: \(label) · tilt \(Self.tilt(pitchDown)) \(tolerance)"
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

    /// Pitch in the `DeviceTilt` convention (+ = down) as words.
    private static func tilt(_ pitchDown: Double) -> String {
        String(format: "%.1f° %@", abs(pitchDown), pitchDown >= 0 ? "down" : "up")
    }
}
