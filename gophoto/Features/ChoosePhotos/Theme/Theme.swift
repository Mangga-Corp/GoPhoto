//
//  Theme.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

enum Theme {
    static let background = dyn(0xF6F3EE, 0x1C1B1A)
    static let surface = dyn(0xFFFFFF, 0x2A2826)
    static let stroke = dyn(0xCFC8BE, 0x514D49)
    static let text = dyn(0x3F3A36, 0xECE7E0)
    static let accent = dyn(0x9DB5A6, 0x6F8A7A)

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? color(dark) : color(light) }
    }
    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
