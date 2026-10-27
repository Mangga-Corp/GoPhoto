import SwiftUI

/// Photo detail: the camera-angle scan result(s) for this photo, with the numbers and time behind them.
struct CameraAngleComparisonCard: View {
    let comparison: CameraAngleComparison
    let selected: CameraAngleMethod

    var body: some View {
        ResultCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Camera angle scan", systemImage: "camera.metering.center.weighted")
                    .font(.subheadline.weight(.semibold))
                let methods = CameraAngleMethod.allCases.filter { comparison.results[$0] != nil }
                ForEach(methods) { method in
                    block(method)
                    if method != methods.last { Divider() }
                }
                if let difference = lightMinusHeavy {
                    Text(difference).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var lightMinusHeavy: String? {
        guard let h = comparison.details[.geoCalibHeavy], let l = comparison.details[.geoCalibLight],
              let hp = h.pitchDown, let lp = l.pitchDown else { return nil }
        var parts = [String(format: "pitch %+.2f°", lp - hp)]
        if let hr = h.roll, let lr = l.roll { parts.append(String(format: "roll %+.2f°", lr - hr)) }
        if let he = h.cameraElevation, let le = l.cameraElevation { parts.append(String(format: "camera vs eyes %+.2f°", le - he)) }
        if let hf = h.focalPx, let lf = l.focalPx, hf > 0 { parts.append(String(format: "focal %+.1f%%", (lf - hf) / hf * 100)) }
        return "Light − Heavy: " + parts.joined(separator: ", ")
    }

    private func block(_ method: CameraAngleMethod) -> some View {
        let result = comparison.results[method]
        let d = comparison.details[method]
        var lines: [String] = []
        if let e = d?.cameraElevation {
            var s = String(format: "camera %.0f° %@ eyes", abs(e), e >= 0 ? "above" : "below")
            if let u = d?.cameraElevationUncertainty { s += String(format: " (±%.0f°)", u) }
            lines.append(s)
        }
        if let p = d?.pitchDown {
            var s = String(format: "tilt %.1f° %@", abs(p), p >= 0 ? "down" : "up")
            if let u = d?.pitchUncertainty { s += String(format: " ±%.1f°", u) }
            lines.append(s)
        }
        if let r = d?.roll {
            var s = String(format: "roll %.1f°", r)
            if let u = d?.rollUncertainty { s += String(format: " ±%.1f°", u) }
            lines.append(s)
        }
        if let h = result?.heightLevel, h != .unknown { lines.append(h.phrase) }
        if let v = d?.vfov { lines.append(String(format: "lens vFoV %.0f°", v)) }
        if let t = d?.totalMs { lines.append(String(format: "%.0f ms", t)) }

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(method.title).font(.footnote.weight(.semibold))
                if method == selected {
                    Text("in use").font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                Spacer()
                Text(result?.category.label ?? "—").font(.footnote.weight(.semibold))
                    .foregroundStyle(result?.assessment.isDetermined == true ? Color.primary : Color.secondary)
            }
            if let error = d?.error {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else if !lines.isEmpty {
                Text(lines.joined(separator: " · ")).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let result, !result.assessment.isDetermined, d?.error == nil {
                Text(result.assessment.explanation).font(.caption2).foregroundStyle(.tertiary).lineLimit(3)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
