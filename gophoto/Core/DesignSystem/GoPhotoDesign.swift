import SwiftUI

enum GoPhotoDesign {
    static let background = Color.white
    static let primaryText = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    static let secondaryText = Color(red: 133 / 255, green: 133 / 255, blue: 133 / 255)
    static let purple = Color(red: 146 / 255, green: 131 / 255, blue: 189 / 255)
    static let groupedBackground = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let subtleSurface = purple.opacity(0.10)

    // Session setup screens (Preference Selection, Shot Size Selection), from the approved mockups.
    static let sessionBackground = Color(red: 248 / 255, green: 247 / 255, blue: 251 / 255)
    static let sessionBarBackground = Color(red: 252 / 255, green: 251 / 255, blue: 254 / 255)
    /// Deeper purple of the mockups' Continue button and checkmarks.
    static let sessionAccent = Color(red: 99 / 255, green: 84 / 255, blue: 143 / 255)
    static let selectedCardBackground = Color(red: 238 / 255, green: 234 / 255, blue: 246 / 255)
    static let neutralCardBackground = Color(red: 241 / 255, green: 240 / 255, blue: 245 / 255)
    static let chipBackground = Color(red: 241 / 255, green: 241 / 255, blue: 244 / 255)
    static let tagBackground = Color(red: 231 / 255, green: 227 / 255, blue: 242 / 255)
    static let tagText = Color(red: 94 / 255, green: 83 / 255, blue: 131 / 255)
    static let cardCornerRadius: CGFloat = 18
    static let sessionMargin: CGFloat = 20

    static let headline = Font.system(size: 34, weight: .bold)
    static let body = Font.system(size: 18, weight: .regular)
    static let primaryButton = Font.system(size: 17, weight: .semibold)
    static let buttonHeight: CGFloat = 62
    static let buttonCornerRadius: CGFloat = 24
    static let horizontalMargin: CGFloat = 30
}
