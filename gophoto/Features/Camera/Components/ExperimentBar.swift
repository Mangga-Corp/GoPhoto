//
//  ExperimentBar.swift
//  gophoto
//
//  appMode 2 only: guide + framing pickers above the shot sizes, and the "i" sheet that explains
//  every option. Spec: Docs/Experiments/PhaseGuide/Spec-v3.md §1.
//
import SwiftUI

struct ExperimentBar: View {
    @Binding var selection: ExperimentSelection
    let depthSupport: LiveDepthSupport
    var onInfo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(ExperimentGuide.allCases) { guide in
                    let blocked = guide.usesDepth && !depthSupport.available
                    Button {
                        selection.guide = guide
                    } label: {
                        if selection.guide == guide {
                            Label(guide.title, systemImage: "checkmark")
                        } else {
                            Text(guide.title)
                        }
                        if blocked { Text(depthSupport.note) }
                    }
                    .disabled(blocked)
                }
            } label: {
                chip("Guide", selection.guide.title)
            }
            .accessibilityLabel("Guide: \(selection.guide.title)")

            Menu {
                ForEach(FramingPolicy.allCases) { framing in
                    Button {
                        selection.framing = framing
                    } label: {
                        if selection.framing == framing {
                            Label(framing.title, systemImage: "checkmark")
                        } else {
                            Text(framing.title)
                        }
                    }
                }
            } label: {
                chip("Framing", selection.guide.isPhased ? selection.framing.title : "—")
            }
            .disabled(!selection.guide.isPhased)
            .opacity(selection.guide.isPhased ? 1 : 0.45)
            .accessibilityLabel(selection.guide.isPhased ? "Framing: \(selection.framing.title)"
                                                         : "Framing applies to the Phased guides only")

            Button(action: onInfo) {
                Image(systemName: "info.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("About the guides")
        }
    }

    private func chip(_ caption: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(caption).font(.caption2).foregroundStyle(.white.opacity(0.7))
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(.yellow)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.white.opacity(0.12), in: Capsule())
    }
}

/// The "i" sheet: what each guide and framing does, and what this iPhone supports.
struct ExperimentInfoSheet: View {
    let selection: ExperimentSelection
    let depthSupport: LiveDepthSupport
    let photoMegapixels: Double?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Now") {
                    Text(selection.label).font(.headline)
                }
                Section("Guide") {
                    ForEach(ExperimentGuide.allCases) { guide in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(guide.title).font(.subheadline.weight(.semibold))
                            Text(guide.summary).font(.footnote).foregroundStyle(.secondary)
                            if guide.usesDepth {
                                Text(depthSupport.available ? "Available on this iPhone · photos about 12 MP"
                                                            : "Not available: \(depthSupport.note)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(depthSupport.available ? Color.green : Color.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    ForEach(FramingPolicy.allCases) { framing in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(framing.title).font(.subheadline.weight(.semibold))
                            Text(framing.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Framing (Phased guides only)")
                } footer: {
                    Text("Main and Main modified ignore the framing choice: they keep their own behaviour.")
                }
                Section("Photo size") {
                    LabeledContent("Largest on this camera",
                                   value: photoMegapixels.map { String(format: "%.0f MP", $0) } ?? "—")
                    LabeledContent("Auto crop floor", value: "12 MP (8 MP with depth)")
                    LabeledContent("No crop / 2×", value: "about 12 MP")
                }
                Section("Log") {
                    Text("Every instruction change and every shutter is logged with the guide and framing (debug panel → Share log).")
                        .font(.footnote)
                }
            }
            .navigationTitle("Guides")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
