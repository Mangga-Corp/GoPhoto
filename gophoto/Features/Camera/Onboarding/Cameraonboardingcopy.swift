//
//  Cameraonboardingcopy.swift
//  gophoto
//
//  Created by Sebastian Darren on 05/11/26.
//

import Foundation
 
enum CameraOnboardingStep: Int, CaseIterable {
    case shotCards
    case sitting
    case heightUp
    case heightDown
    case tiltDown
    case tiltUp      

    var title: String {
        switch self {
        case .shotCards:    "Pick a shot size"
        case .sitting:      "Sitting? It adapts"
        case .tiltDown:     "Tilt the phone down"
        case .tiltUp:       "Tilt the phone up"
        case .heightUp:     "Raise the phone"
        case .heightDown:   "Lower the phone"
        }
    }
 
    var message: String {
        switch self {
        case .shotCards:
            "These cards follow your reference photos: Full body, 3/4 or Half body. Swipe left or right to switch."
        case .sitting:
            "When your subject sits down, the cards change to sitting and only Full body is offered."
        case .tiltDown:
            "When you see this animation, tilt the top of your phone down until it matches your reference photos."
        case .tiltUp:
            "When you see this animation, tilt the top of your phone up until it matches your reference photos."
        case .heightUp:
            "When you see this animation, raise your phone higher and keep the same angle."
        case .heightDown:
            "When you see this animation, lower your phone and keep the same angle."
        }
    }
}
 
enum CameraOnboardingCopy {
    static let continueButton = "Continue"
    static let finishButton = "Finish"
 
    // Sama dengan ShotSizePicker.postureCaption
    static let standingCaption = "Standing"
    static let sittingCaption = "Sitting · full body only"
}
