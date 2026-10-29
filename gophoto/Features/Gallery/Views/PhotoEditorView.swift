//
//  PhotoEditorView.swift
//  gophoto
//
//  Full-screen editor, opened from the viewer's Edit button (like the Photos app).
//  Cancel (top left) and Save (top right) never change while editing: only the tool area at the
//  bottom switches between AI Enhanced looks and manual sliders. Saving writes a NEW photo; the
//  original is never touched.
//

import SwiftUI

struct PhotoEditorView: View {
    let assetID: String
    let createdAt: Date
    let loadImage: (String, CGSize) async -> UIImage?
    let loadThumbnail: (String, CGSize) async -> UIImage?
    /// (presetID, settings) → error message, or nil once the edited copy is saved
    let onSave: (PhotoEnhancer.Settings) async -> String?
    /// Called after a successful save, once the editor is closed
    let onSaved: () -> Void

    private enum Tool: String, CaseIterable, Identifiable {
        case looks = "Filter"
        case adjust = "Adjust"
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tool: Tool = .looks
    @State private var selectedLook: EnhancedLook?
    /// Slider values and the AI Enhance values they started from (nil until measured)
    @State private var adjustments: PhotoEnhancer.Settings?
    @State private var baseline: PhotoEnhancer.Settings?
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @State private var errorMessage: String?

    private var hasChanges: Bool {
        if let adjustments { return adjustments != baseline || selectedLook != nil }
        return selectedLook != nil
    }

    var body: some View {
        NavigationStack {
            FullPhotoView(assetID: assetID,
                          createdAt: createdAt,
                          loadImage: loadImage,
                          look: tool == .looks ? selectedLook : nil,
                          adjustments: tool == .adjust ? adjustments : nil)
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) {
                            if hasChanges { isConfirmingDiscard = true } else { dismiss() }
                        }
                        .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save", role: .confirm) { Task { await save() } }
                                .disabled(!hasChanges)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { toolArea }
        }
        // Swiping the sheet away must not lose work or interrupt a save
        .interactiveDismissDisabled(hasChanges || isSaving)
        // An alert, not a confirmationDialog: from a toolbar button iOS shows the dialog as a
        // popover without its Cancel button, leaving only "Discard Changes".
        .alert("Discard your edits?", isPresented: $isConfirmingDiscard) {
            Button("Discard Changes", role: .destructive) { dismiss() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your changes won't be saved.")
        }
        .alert("Couldn't Save", isPresented: Binding(get: { errorMessage != nil },
                                                    set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: tool) { _, newTool in
            if newTool == .adjust, adjustments == nil { Task { await startAdjusting() } }
        }
        .onChange(of: selectedLook) {
            // The sliders start from the AI values of the look, so they must be measured again
            adjustments = nil
            baseline = nil
            if tool == .adjust { Task { await startAdjusting() } }
        }
        .sensoryFeedback(.selection, trigger: selectedLook)
    }

    // MARK: - Tool area

    private var toolArea: some View {
        VStack(spacing: 12) {
            Picker("Tool", selection: $tool) {
                ForEach(Tool.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .disabled(isSaving)

            switch tool {
            case .looks:
                LookPickerView(assetID: assetID,
                               selection: $selectedLook,
                               loadThumbnail: loadThumbnail)
            case .adjust:
                if let binding = Binding($adjustments) {
                    AdjustPanelView(settings: binding, baseline: baseline)
                } else {
                    ProgressView("Analysing photo…")
                        .frame(height: 120)
                }
            }
        }
        .padding(.bottom, 8)
        .disabled(isSaving)
        .background(.bar)
    }

    // MARK: - Actions

    /// Opens the sliders at the AI Enhance values of the photo (in the selected look).
    private func startAdjusting() async {
        let look = selectedLook
        // Screen-sized is enough to measure the photo; the full-resolution save reuses these values
        guard let image = await loadImage(assetID, CGSize(width: 1024, height: 1024)) else {
            errorMessage = "The photo could not be loaded."
            tool = .looks
            return
        }
        let measured = await Task.detached(priority: .userInitiated) {
            PhotoEnhancer().baselineSettings(for: image, look: look)
        }.value
        guard look == selectedLook, tool == .adjust, let measured else { return }
        baseline = measured
        adjustments = measured
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        // Sliders win when they were opened; otherwise the selected look is measured like the sliders
        var settings = tool == .adjust ? adjustments : nil
        if settings == nil, let look = selectedLook {
            guard let image = await loadImage(assetID, CGSize(width: 1024, height: 1024)) else {
                errorMessage = "The photo could not be loaded."
                return
            }
            settings = await Task.detached(priority: .userInitiated) {
                PhotoEnhancer().baselineSettings(for: image, look: look)
            }.value
        }
        guard let settings else { return }

        if let error = await onSave(settings) {
            errorMessage = error
        } else {
            dismiss()
            onSaved()
        }
    }
}
