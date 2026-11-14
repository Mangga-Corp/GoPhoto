//
//  ReplayControls.swift
//  gophoto
//
//  appMode 2 testing: Replay video controls (replace the shutter row) and the video preview.
//  The shutter becomes "Save test frame" (results folder, never the photo library).
//
import SwiftUI

struct ReplayControls: View {
    let info: ReplayVideoInfo?
    let time: Double
    let playing: Bool
    let ended: Bool
    let scenario: ReplayScenario
    let exports: [URL]
    let message: String?
    /// "Run all 3/12 · …" while a batch runs.
    let batchStatus: String?
    var onPickFiles: () -> Void
    var onPickPhotos: () -> Void
    var onPlayPause: () -> Void
    var onRestart: () -> Void
    var onSaveFrame: () -> Void
    var onEndRun: () -> Void
    var onScenario: (ReplayScenario) -> Void
    var onLive: () -> Void
    var onRunAll: ([ReplayScenario]) -> Void
    var onStopBatch: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Menu {
                    Button("From Files…", systemImage: "folder", action: onPickFiles)
                    Button("From Photos…", systemImage: "photo.on.rectangle", action: onPickPhotos)
                } label: {
                    Label(info?.name ?? "Choose video", systemImage: "film")
                        .font(AppFont.footnote.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .accessibilityLabel(info == nil ? "Choose a test video" : "Change test video")
                if let info {
                    Text(String(format: "%@ / %@", Self.clock(time), Self.clock(info.duration)))
                        .font(AppFont.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                }
                Menu {
                    if batchStatus != nil {
                        Button("Stop run all", systemImage: "stop.fill", role: .destructive, action: onStopBatch)
                    } else {
                        Button("All guides · RGB observation") { onRunAll([.rgbObservation]) }
                        Button("All guides · Distance locked (simulation)") { onRunAll([.distanceLocked]) }
                        Button("All guides · both scenarios") { onRunAll([.rgbObservation, .distanceLocked]) }
                    }
                } label: {
                    Label("Run all", systemImage: batchStatus == nil ? "square.stack.3d.down.forward" : "stop.circle")
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(batchStatus == nil ? .white : .orange)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .disabled(info == nil)
                .accessibilityLabel(batchStatus == nil ? "Run all guides, framings and shot sizes" : "Stop run all")
            }
            if let batchStatus {
                Text(batchStatus)
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            HStack(spacing: 14) {
                icon("arrow.uturn.backward.circle", "Back to live camera", action: onLive)
                icon("backward.end.fill", "Restart from the beginning", action: onRestart).disabled(info == nil)
                Button(action: onPlayPause) {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(AppFont.system(size: 52))
                        .foregroundStyle(.white)
                }
                .disabled(info == nil)
                .accessibilityLabel(playing ? "Pause" : (ended ? "Play again from the start" : "Play"))
                icon("square.and.arrow.down", "Save test frame", action: onSaveFrame).disabled(info == nil)
                Menu {
                    ForEach(ReplayScenario.allCases) { s in
                        Button {
                            onScenario(s)
                        } label: {
                            if s == scenario { Label(s.title, systemImage: "checkmark") } else { Text(s.title) }
                        }
                    }
                } label: {
                    Image(systemName: scenario == .distanceLocked ? "lock.square" : "eye.square")
                        .font(AppFont.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Test scenario: \(scenario.title)")
                if exports.isEmpty {
                    icon("stop.circle", "End run and prepare the export", action: onEndRun).disabled(info == nil)
                } else {
                    ShareLink(items: exports) {
                        Image(systemName: "square.and.arrow.up")
                            .font(AppFont.title2)
                            .foregroundStyle(.yellow)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Export run results")
                }
            }
            if let message {
                Text(message)
                    .font(AppFont.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
    }

    private func icon(_ name: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(AppFont.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%05.2f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }
}

/// The video frame, fitted (letterboxed) in the preview area. Overlays passed in are laid over the
/// video's own rectangle, so normalized frame coordinates (masks, crops, taps) line up with it.
struct ReplayPreview<Overlay: View>: View {
    let image: CGImage?
    let aspect: Double
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack {
            Color.black
            Group {
                if let image {
                    Image(decorative: image, scale: 1).resizable()
                } else {
                    Color(white: 0.08).overlay {
                        Text("Choose a video to replay")
                            .font(AppFont.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .overlay { overlay() }
        }
    }
}

/// Permanent labels on a replay preview.
struct ReplayBadges: View {
    let simulation: Bool
    let maskNote: String?

    var body: some View {
        VStack(spacing: 4) {
            if let maskNote {
                Text(maskNote)
                    .font(AppFont.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.6), in: Capsule())
            }
            HStack(spacing: 6) {
                Text("Replay · RGB only")
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.blue.opacity(0.75), in: Capsule())
                if simulation {
                    Text("State simulation")
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.85), in: Capsule())
                }
            }
            .font(AppFont.caption2.weight(.bold))
            .foregroundStyle(.white)
        }
        .padding(.bottom, 8)
        .allowsHitTesting(false)
    }
}
