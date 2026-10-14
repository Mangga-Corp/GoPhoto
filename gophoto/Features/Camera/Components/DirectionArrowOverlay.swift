//
//  DirectionArrowOverlay.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 13/10/26.
//
import SwiftUI

struct DirectionArrowOverlay: View {
    let instruction: GuideInstruction

    private let arrowColor = Color(red: 0.98, green: 0.78, blue: 0.46)   // mockup yellow

    var body: some View {
        ZStack(alignment: alignment) {
            Color.clear   // fills the image so the arrow can sit at an edge

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(arrowColor)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .symbolEffect(.pulse, options: .repeating)
                    .padding(padding)
                    .id(instruction)            // new arrow = fresh animation
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: instruction)
        .allowsHitTesting(false)
        .accessibilityHidden(true)              // the pill already says it
    }

    private var symbol: String? {
        switch instruction {
        case .moveLeft:    "chevron.left"
        case .moveRight:   "chevron.right"
        case .moveHigher:  "chevron.up"
        case .moveLower:   "chevron.down"
        case .moveCloser:  "arrow.up.left.and.arrow.down.right"
        case .moveFarther: "arrow.down.right.and.arrow.up.left"
        default:           nil
        }
    }

    private var alignment: Alignment {
        switch instruction {
        case .moveLeft:    .leading
        case .moveRight:   .trailing
        case .moveHigher:  .top
        case .moveLower, .moveFarther: .bottom
        default:           .center
        }
    }

    private var padding: EdgeInsets {
        instruction == .moveHigher
            ? EdgeInsets(top: 56, leading: 0, bottom: 0, trailing: 0)   // below the pill
            : EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
    }
}
