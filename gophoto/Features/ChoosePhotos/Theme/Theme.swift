//
//  Theme.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

/// UIKit view of `GoPhotoDesign`: the same tokens as `UIColor`/`UIFont`, so UIKit screens never
/// define their own colors.
enum Theme {
    static let background = UIColor(GoPhotoDesign.background)
    static let surface = UIColor(GoPhotoDesign.surface)
    static let stroke = UIColor(GoPhotoDesign.border)
    static let divider = UIColor(GoPhotoDesign.divider)
    static let text = UIColor(GoPhotoDesign.primaryText)
    static let secondaryText = UIColor(GoPhotoDesign.secondaryText)
    static let disabledText = UIColor(GoPhotoDesign.disabledText)
    static let accent = UIColor(GoPhotoDesign.primary)
    static let accentPressed = UIColor(GoPhotoDesign.primaryPressed)
    static let accentSubtle = UIColor(GoPhotoDesign.primarySubtle)
    static let accentBorder = UIColor(GoPhotoDesign.primaryBorder)
    static let tagBackground = UIColor(GoPhotoDesign.tagBackground)
    static let tagText = UIColor(GoPhotoDesign.tagText)
    static let disabledFill = UIColor(GoPhotoDesign.secondaryBackground)
    static let destructive = UIColor(GoPhotoDesign.error)
    static let onAccent = UIColor(GoPhotoDesign.onPrimary)
    static let cardCornerRadius = GoPhotoDesign.cardCornerRadius
    static let buttonHeight = GoPhotoDesign.buttonHeight
}
