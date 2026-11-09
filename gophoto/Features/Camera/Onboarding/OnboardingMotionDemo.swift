//
//  OnboardingMotionDemo.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import SwiftUI
 
struct OnboardingMotionDemo: View {
    enum Kind { case tilt, height }
    let kind: Kind
    let direction: Direction
 
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
 
    private var instruction: GuideInstruction {
        switch (kind, direction) {
        case (.tilt, .up):     .tiltUp
        case (.tilt, .down):   .tiltDown
        case (.height, .up):   .raisePhone
        case (.height, .down): .lowerPhone
        }
    }
 
    var body: some View {
        GeometryReader { proxy in
            // Ukuran & posisi persis seperti GuidanceMotionOverlay
            let fraction = min(max(GuidanceAnimationStyle.sizeFraction, 0.15), 0.5)
            let height = proxy.size.height * fraction
            let width = height * 0.72
            let gridLineX = proxy.size.width / 3.0
            let centerY = proxy.size.height / 2.0
 
            ZStack {
                switch kind {
                case .tilt:
                    TiltGuidanceView(direction: direction,
                                     degrees: GuidanceMotion.tiltFallbackDegrees,
                                     tiltView: GuidanceAnimationStyle.tiltView,
                                     isActive: !reduceMotion,
                                     guideColor: GuidanceAnimationStyle.guideColor,
                                     showsStillPose: reduceMotion)
                        .id("tilt-\(direction)")
                        .frame(width: width, height: height)
                        .position(x: gridLineX, y: centerY)
                        .transition(.opacity)
 
                    CurvedRacingArrowView(direction: direction)
                        .id("tilt-arrow-\(direction)")
                        .position(x: gridLineX, y: centerY - (height / 2) + 5)
                        .transition(.opacity)
 
                case .height:
                    HeightGuidanceView(direction: direction,
                                       isActive: !reduceMotion,
                                       yawDegrees: GuidanceAnimationStyle.heightYawDegrees,
                                       guideColor: GuidanceAnimationStyle.guideColor,
                                       showsStillPose: reduceMotion)
                        .id("height-\(direction)")
                        .frame(width: width, height: height)
                        .position(x: gridLineX, y: centerY)
                        .transition(.opacity)
 
                    RacingArrowView(direction: direction == .up ? .up : .down)
                        .id("height-arrow-\(direction)")
                        .position(x: gridLineX,
                                  y: direction == .up ? centerY - (height / 2) - 26
                                                      : centerY + (height / 2) + 26)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) {
            // Pill yang sama dengan pill asli di atas tengah
            InstructionPill(instruction: instruction)
                .background { Capsule().fill(Color.black).frame(width: 280, height: 40) }
                .padding(.top, 12)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
