//
//  TiltIndicatorView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 10/10/26.
//
//
//  TiltIndicatorView.swift
//  gophoto
//

import SwiftUI

/// Small pill showing the tilt. Turns yellow when level.
/// Takes plain values only, so it knows nothing about the ViewModel.
struct TiltIndicatorView: View {
    let degrees: Int
    let isLevel: Bool

    var body: some View {
        Text("\(degrees)°")
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(isLevel ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isLevel ? Color.yellow : Color.black.opacity(0.4), in: Capsule())
            .animation(.snappy, value: degrees)
            .animation(.snappy, value: isLevel)
            .accessibilityLabel(isLevel ? "Level" : "Tilted \(degrees) degrees")
    }
}

#Preview {
    VStack(spacing: 16) {
        TiltIndicatorView(degrees: 7, isLevel: false)
        TiltIndicatorView(degrees: 0, isLevel: true)
    }
    .padding(40)
    .background(.gray)
}
