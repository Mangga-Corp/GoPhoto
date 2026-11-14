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
        case .shotCards:    "Choose your shot"
        case .sitting:      "Sitting? We adapt"
        case .tiltDown:     "Tilt down"
        case .tiltUp:       "Tilt up"
        case .heightUp:     "Raise your phone"
        case .heightDown:   "Lower your phone"
        }
    }
 
    var message: String {
        switch self {
        case .shotCards:
            "Swipe to switch between Full, 3/4 or Half Body. They match your reference photos."
        case .sitting:
            "When you sit, only Full Body is offered."
        case .tiltDown:
            "See this? Tilt the top of your phone down to match your reference photos."
        case .tiltUp:
            "See this? Tilt the top of your phone up to match your reference photos."
        case .heightUp:
            "See this? Lift your phone higher and keep the same tilt."
        case .heightDown:
            "See this? Lower your phone and keep the same tilt."
        }
    }
}
 
enum CameraOnboardingCopy {
    static let continueButton = "Continue"
    static let finishButton = "Finish"
 }
