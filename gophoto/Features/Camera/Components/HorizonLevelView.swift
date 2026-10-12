//
//  HorizonLevelView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 12/10/26.
//
import SwiftUI

struct HorizonLevelView: View {
    let state: HorizonState

    @State private var hasFaded = false   // only for the "yellow, then fade" effect

    private var isLevel: Bool { state == .level }

    private var isVisible: Bool {
        switch state {
        case .hidden:  false
        case .tilted:  true
        case .level:   !hasFaded
        }
    }

    var body: some View {
        let color: Color = isLevel ? .yellow : .white

        HStack(spacing: 8) {
            segment(width: 28, color: color)                     // fixed: phone's level
            segment(width: 120, color: color)
                .rotationEffect(.degrees(-state.roll))           // real horizon
            segment(width: 28, color: color)                     // fixed: phone's level
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        .animation(.snappy, value: isLevel)
        .task(id: isLevel) {
            // Each time it becomes level: show yellow briefly, then fade
            hasFaded = false
            guard isLevel else { return }
            do {
                try await Task.sleep(for: .seconds(0.6))
                hasFaded = true
            } catch {
                // cancelled because the phone tilted again → stay visible
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)   // the haptic already signals "level"
    }

    private func segment(width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: 2)
            .shadow(color: .black.opacity(0.4), radius: 1)   // readable on bright scenes
    }
}

#Preview {
    VStack(spacing: 40) {
        HorizonLevelView(state: .tilted(degrees: 6))
        HorizonLevelView(state: .tilted(degrees: -3))
        HorizonLevelView(state: .level)
    }
    .padding(40)
    .background(.gray)
}
