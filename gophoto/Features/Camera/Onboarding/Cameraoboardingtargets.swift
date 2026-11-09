//
//  Cameraoboardingtargets.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import SwiftUI
 
enum CameraOnboardingTarget: Hashable {
    case preview    // area preview kamera (tempat pill guidance & animasi)
    case shutter    // dipakai untuk menentukan posisi demo card shot size
}
 
extension View {
    /// Menyimpan frame view ini (koordinat global) ke `frames`. Tidak mengubah tampilan.
    func reportOnboardingFrame(
        _ target: CameraOnboardingTarget,
        into frames: Binding<[CameraOnboardingTarget: CGRect]>
    ) -> some View {
        onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            frames.wrappedValue[target] = frame
        }
    }
}
