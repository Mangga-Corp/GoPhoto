//
//  GuidanceGalleryView.swift
//  gophoto
//
//  Created by Sebastian Darren on 31/10/26.
//

#if DEBUG
import SwiftUI

struct GuidanceGalleryView: View {
    enum DemoMode: String, CaseIterable, Identifiable {
        case tiltDown = "Tilt Down"
        case tiltUp = "Tilt Up"
        case raisePhone = "Height (Raise)"
        case lowerPhone = "Height (Lower)"
        case ready = "Capture it"

        var id: String { rawValue }

        var instruction: GuideInstruction {
            switch self {
            case .tiltDown:   return .tiltDown
            case .tiltUp:     return .tiltUp
            case .raisePhone: return .raisePhone
            case .lowerPhone: return .lowerPhone
            case .ready:      return .holdStill
            }
        }
    }

    @State private var mode: DemoMode = .tiltDown
    @State private var backdrop: GalleryBackdrop = .dark
    @State private var speed: Double = 1.0
    @State private var pitchError: Double = 25.0

    var body: some View {
        VStack(spacing: 14) {
            // Kontrol Mode
            Picker("Mode", selection: $mode) {
                ForEach(DemoMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Kontrol Background
            Picker("Background", selection: $backdrop) {
                ForEach(GalleryBackdrop.allCases) { b in
                    Text(b.rawValue).tag(b)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Area Panggung Utama Simulasi Kamera
            ZStack {
                // Background pilihan
                RoundedRectangle(cornerRadius: 24)
                    .fill(backdrop.style)

                // Grid rule of thirds simulasi kamera
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    Path { p in
                        // Garis vertikal 1/3 dan 2/3
                        p.move(to: CGPoint(x: w / 3, y: 0))
                        p.addLine(to: CGPoint(x: w / 3, y: h))
                        p.move(to: CGPoint(x: w * 2 / 3, y: 0))
                        p.addLine(to: CGPoint(x: w * 2 / 3, y: h))
                        // Garis horizontal 1/3 dan 2/3
                        p.move(to: CGPoint(x: 0, y: h / 3))
                        p.addLine(to: CGPoint(x: w, y: h / 3))
                        p.move(to: CGPoint(x: 0, y: h * 2 / 3))
                        p.addLine(to: CGPoint(x: w, y: h * 2 / 3))
                    }
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }

                // Overlay animasi aktif dengan mockup HP 3D & Arrow
                GuidanceMotionOverlay(
                    instruction: mode.instruction,
                    pitchError: mode == .tiltDown ? -pitchError : pitchError,
                    isEnabled: true
                )

                // Instruction pill di bagian atas
                VStack {
                    InstructionPill(instruction: mode.instruction)
                        .padding(.top, 20)
                    Spacer()
                }
            }
            .frame(height: 380)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal)

            // Panel Inspeksi Khusus Detail Arrow (Tilting & Height)
            VStack(alignment: .leading, spacing: 8) {
                Text("Arrow Detail (Tilting Melengkung & Height)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    // Arrow Tilt Down (melengkung ke kanan bawah)
                    VStack(spacing: 4) {
                        Text("Kanan Bawah (Down)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.75))
                            CurvedRacingArrowView(direction: .down, speedMultiplier: speed)
                        }
                        .frame(width: 90, height: 60)
                    }

                    // Arrow Tilt Up (melengkung ke kiri bawah)
                    VStack(spacing: 4) {
                        Text("Kiri Bawah (Up)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.75))
                            CurvedRacingArrowView(direction: .up, speedMultiplier: speed)
                        }
                        .frame(width: 90, height: 60)
                    }

                    // Height Lower (turun)
                    VStack(spacing: 4) {
                        Text("Lower (Turun)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.75))
                            RacingArrowView(direction: .down)
                        }
                        .frame(width: 70, height: 60)
                    }

                    // Height Raise (naik)
                    VStack(spacing: 4) {
                        Text("Raise (Naik)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.black.opacity(0.75))
                            RacingArrowView(direction: .up)
                        }
                        .frame(width: 70, height: 60)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Kontrol Kecepatan Animasi
            HStack {
                Text("Kecepatan:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker("Speed", selection: $speed) {
                    Text("0.5×").tag(0.5)
                    Text("0.75×").tag(0.75)
                    Text("1.0×").tag(1.0)
                    Text("1.25×").tag(1.25)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)

            Spacer(minLength: 8)
        }
        .padding(.vertical)
        .navigationTitle("Guidance Animation Test")
    }
}

// MARK: - Xcode Previews (Dapat diuji langsung di Mac tanpa membuka handphone)

#Preview("Guidance Animation Gallery - Dark") {
    NavigationStack {
        GuidanceGalleryView()
    }
}

#Preview("Curved Tilting Arrow Alone") {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 30) {
            Text("Tilt Down (Condong Depan)")
                .foregroundStyle(.white)
            CurvedRacingArrowView(direction: .down)

            Divider().background(Color.gray)

            Text("Tilt Up (Condong Belakang)")
                .foregroundStyle(.white)
            CurvedRacingArrowView(direction: .up)
        }
        .padding()
    }
}
#endif
