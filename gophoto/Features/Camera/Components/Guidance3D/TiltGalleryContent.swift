//
//  TiltGalleryContent.swift
//  gophoto
//
//  Created by Sebastian Darren on 29/10/26.
//

#if DEBUG
import SwiftUI

struct TiltGalleryContent: View {
    let backdrop: GalleryBackdrop

    @State private var speed = 1.0
    @State private var isPlaying = true
    @State private var degrees = 25.0

    private var shownDegrees: Int { Int(GuidanceMotion.tiltDegrees(forPitchError: degrees).rounded()) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GalleryStage(title: "Tilt up ▲ · front", backdrop: backdrop, height: 340) {
                    TiltGuidanceView(direction: .up, degrees: degrees, tiltView: .frontFacing,
                                     isActive: isPlaying, speed: speed, guideColor: backdrop.guideColor)
                }
                GalleryStage(title: "Tilt down ▼ · front", backdrop: backdrop, height: 340) {
                    TiltGuidanceView(direction: .down, degrees: degrees, tiltView: .frontFacing,
                                     isActive: isPlaying, speed: speed, guideColor: backdrop.guideColor)
                }
            }
            Picker("Speed", selection: $speed) {
                Text("0.25×").tag(0.25)
                Text("0.5×").tag(0.5)
                Text("1×").tag(1.0)
            }
            .pickerStyle(.segmented)
            Toggle("Playing", isOn: $isPlaying)
            HStack {
                Text("Input").font(.footnote).frame(width: 50, alignment: .leading)
                Slider(value: $degrees, in: 0...60)
                Text("\(Int(degrees))° → \(shownDegrees)°")
                    .font(.footnote.monospacedDigit())
                    .frame(width: 84, alignment: .trailing)
            }
        }
    }
}
#endif
