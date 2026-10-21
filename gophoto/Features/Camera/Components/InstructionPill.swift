//
//  InstructionPill.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 13/10/26.
//
import SwiftUI

struct InstructionPill: View {
    let instruction: GuideInstruction

    private var isReady: Bool { instruction == .holdStill }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isReady ? Color.green.opacity(0.85) : Color.black.opacity(0.6), in: Capsule())
        .animation(.snappy, value: instruction)
        .accessibilityElement(children: .combine)
    }

    // The View decides the words (LocalizedStringKey → translatable later)
    private var title: LocalizedStringKey {
        switch instruction {
        case .findPerson:  "Find the person"
        case .moveCloser:  "Move closer"
        case .moveFarther: "Move farther away"
        case .moveLeft:    "Move left"
        case .moveRight:   "Move right"
        case .moveHigher:  "Move higher"
        case .moveLower:   "Move lower"
        case .tiltUp:      "Tilt the phone up"
        case .tiltDown:    "Tilt the phone down"
        case .straighten:  "Straighten the phone"
        case .holdStill:   "Hold still"
        }
    }

    private var symbol: String {
        switch instruction {
        case .findPerson:  "person.crop.rectangle"
        case .moveCloser:  "arrow.up.left.and.arrow.down.right"
        case .moveFarther: "arrow.down.right.and.arrow.up.left"
        case .moveLeft:    "arrow.left"
        case .moveRight:   "arrow.right"
        case .moveHigher:  "arrow.up"
        case .moveLower:   "arrow.down"
        case .tiltUp:      "arrow.up.circle"
        case .tiltDown:    "arrow.down.circle"
        case .straighten:  "level"
        case .holdStill:   "checkmark"
        }
    }
}

#Preview {
    VStack(spacing: 10) {
        ForEach(GuideInstruction.allCases, id: \.self) { instruction in
            InstructionPill(instruction: instruction)
        }
    }
    .padding()
    .background(.gray)
}
