//
//  HeightGalleryContent.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

#if DEBUG
import SwiftUI

struct HeightGalleryContent: View {
    let backdrop: GalleryBackdrop

    @State private var speed = 1.0
    @State private var isPlaying = true
    @State private var angled = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                GalleryStage(title: "Raise ▲", backdrop: backdrop, height: 340) {
                    HeightGuidanceView(direction: .up, isActive: isPlaying, speed: speed,
                                       yawDegrees: angled ? 20 : 0, guideColor: backdrop.guideColor)
                }
                GalleryStage(title: "Lower ▼", backdrop: backdrop, height: 340) {
                    HeightGuidanceView(direction: .down, isActive: isPlaying, speed: speed,
                                       yawDegrees: angled ? 20 : 0, guideColor: backdrop.guideColor)
                }
            }
            Picker("Speed", selection: $speed) {
                Text("0.25×").tag(0.25)
                Text("0.5×").tag(0.5)
                Text("1×").tag(1.0)
            }
            .pickerStyle(.segmented)
            Toggle("Playing", isOn: $isPlaying)
            Toggle("3D angle (20°) instead of flat front", isOn: $angled)
        }
    }
}
#endif
