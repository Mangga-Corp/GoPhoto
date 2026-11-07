//
//  Theme.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

enum Theme {
    static let background = UIColor(GoPhotoDesign.background)
    static let surface = UIColor(GoPhotoDesign.background)
    static let stroke = UIColor(GoPhotoDesign.secondaryText).withAlphaComponent(0.22)
    static let text = UIColor(GoPhotoDesign.primaryText)
    static let accent = UIColor(GoPhotoDesign.purple)
    static let tagBackground = UIColor(GoPhotoDesign.tagBackground)
    static let onAccent = UIColor.white
}
