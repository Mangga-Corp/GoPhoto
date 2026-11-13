//
//  GroundTruthSheet.swift
//  gophoto
//
//  appMode 2 GT recording (12 Nov): after a shutter, what was really true for that photo.
//  Heights measured with a tape are the best ground truth; the level picker is the fallback.
//  The subject's eye height is remembered (same person over a session).
//
import SwiftUI

struct GroundTruthSheet: View {
    @State var entry: GroundTruthEntry
    var onSave: (GroundTruthEntry) -> Void

    @AppStorage("gt.eyeHeightCm") private var lastEyeHeight: Double = 0
    @State private var cameraText = ""
    @State private var eyeText = ""

    private static let levels: [(String, String)] = [
        ("aboveHead", "Above head"), ("eye", "Eyes"), ("shoulder", "Chin–chest"),
        ("hip", "Waist / hips"), ("knee", "Knees"), ("ground", "Near the floor"),
    ]
    private static let postures = ["standing", "leaning", "sitting"]
    private static let facings = ["front", "left", "right", "back"]
    private static let shots: [(String, String)] = [("full", "Full"), ("threeQuarter", "3/4"), ("half", "Half"), ("quarter", "1/4")]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Lens height from floor (cm)", text: $cameraText).keyboardType(.decimalPad)
                    TextField("Subject's eye height from floor (cm)", text: $eyeText).keyboardType(.decimalPad)
                    if let d = difference {
                        Text(String(format: "Camera %.0f cm %@ the eyes", abs(d), d >= 0 ? "above" : "below"))
                            .font(.footnote.weight(.semibold))
                    }
                } header: {
                    Text("Measured (best)")
                } footer: {
                    Text("Measure the lens, not the top of the phone. The eye height is kept for the next photo.")
                }
                Section("If not measured: lens was at the subject's…") {
                    Picker("Level", selection: optional(\.heightLevel)) {
                        Text("—").tag("")
                        ForEach(Self.levels, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("Subject") {
                    Picker("Posture", selection: optional(\.posture)) {
                        Text("—").tag("")
                        ForEach(Self.postures, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Facing (seen from camera)", selection: optional(\.facing)) {
                        Text("—").tag("")
                        ForEach(Self.facings, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    Picker("Shot taken", selection: optional(\.shot)) {
                        Text("—").tag("")
                        ForEach(Self.shots, id: \.0) { Text($0.1).tag($0.0) }
                    }
                }
                Section("Note") {
                    TextField("Anything odd (tilted pillar, crowd, moved…)", text: $entry.note, axis: .vertical)
                }
            }
            .navigationTitle("Ground truth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        var e = entry
                        e.skipped = true
                        onSave(e)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var e = entry
                        e.cameraHeightCm = Self.number(cameraText)
                        e.eyeHeightCm = Self.number(eyeText)
                        if let eye = e.eyeHeightCm { lastEyeHeight = eye }
                        onSave(e)
                    }
                }
            }
            .onAppear { if eyeText.isEmpty, lastEyeHeight > 0 { eyeText = String(format: "%.0f", lastEyeHeight) } }
        }
        .interactiveDismissDisabled()
    }

    private var difference: Double? {
        guard let c = Self.number(cameraText), let e = Self.number(eyeText) else { return nil }
        return c - e
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    /// A Picker binding for an optional String field ("" = not set).
    private func optional(_ key: WritableKeyPath<GroundTruthEntry, String?>) -> Binding<String> {
        Binding(get: { entry[keyPath: key] ?? "" },
                set: { entry[keyPath: key] = $0.isEmpty ? nil : $0 })
    }
}
