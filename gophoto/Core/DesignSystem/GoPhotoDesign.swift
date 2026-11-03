import SwiftUI

enum GoPhotoDesign {
    static let background = Color.white
    static let primaryText = Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255)
    static let secondaryText = Color(red: 133 / 255, green: 133 / 255, blue: 133 / 255)
    static let purple = Color(red: 146 / 255, green: 131 / 255, blue: 189 / 255)
    static let groupedBackground = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let subtleSurface = purple.opacity(0.10)

    static let headline = Font.system(size: 34, weight: .bold)
    static let body = Font.system(size: 18, weight: .regular)
    static let primaryButton = Font.system(size: 17, weight: .semibold)
    static let buttonHeight: CGFloat = 62
    static let buttonCornerRadius: CGFloat = 24
    static let horizontalMargin: CGFloat = 30
}
