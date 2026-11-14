import SwiftUI
import UIKit

extension Color {
    /// `Color(hex: 0x6C30A6)`, sRGB.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The single source of design tokens: color, typography, shape, spacing.
/// UIKit screens read the same values through `Theme` (which wraps these tokens).
enum GoPhotoDesign {

    // MARK: Brand

    /// Canonical brand purple `#6C30A6`. White text on it has a contrast ratio of about 8:1.
    static let primary = Color(hex: 0x6C30A6)
    /// Pressed state of a primary surface.
    static let primaryPressed = Color(hex: 0x55238A)
    /// Selected / tinted background behind primary-colored content.
    static let primarySubtle = Color(hex: 0xEEE5F5)
    /// Border of selected or purple-tinted surfaces.
    static let primaryBorder = Color(hex: 0xDCC9ED)
    static let onPrimary = Color.white

    // MARK: Neutrals

    static let background = Color(hex: 0xFAF8F5)
    static let secondaryBackground = Color(hex: 0xEFE9F3)
    /// Cards and sheets.
    static let surface = Color.white
    static let inputBackground = Color.white

    static let primaryText = Color(hex: 0x29232F)
    /// 5.3:1 on `background`, 4.8:1 on `primarySubtle`.
    static let secondaryText = Color(hex: 0x6A6173)
    static let disabledText = Color(hex: 0x9A91A2)
    static let placeholderText = Color(hex: 0x8A8092)

    static let border = Color(hex: 0xE3DAEA)
    static let divider = Color(hex: 0xEAE3F0)

    // MARK: Semantic (state only, never decoration)

    static let success = Color(hex: 0x1E7A45)
    static let warning = Color(hex: 0x9A5B00)
    static let error = Color(hex: 0xB3261E)
    static let info = Color(hex: 0x1F5FA8)

    // MARK: Typography
    // App font (see AppFont.swift) on Dynamic Type text styles, so every role scales.

    static let largeTitle = AppFont.system(.largeTitle, design: .default, weight: .bold)
    static let pageTitle = AppFont.system(.title, design: .default, weight: .bold)
    static let sectionTitle = AppFont.system(.title3, design: .default, weight: .semibold)
    static let cardTitle = AppFont.system(.headline, design: .default, weight: .semibold)
    static let body = AppFont.system(.body, design: .default, weight: .regular)
    static let secondaryBody = AppFont.system(.subheadline, design: .default, weight: .regular)
    static let caption = AppFont.system(.caption, design: .default, weight: .regular)
    static let buttonLabel = AppFont.system(.headline, design: .default, weight: .semibold)
    static let smallLabel = AppFont.system(.caption, design: .default, weight: .medium)

    // MARK: Shape & spacing

    static let cardCornerRadius: CGFloat = 18
    static let controlCornerRadius: CGFloat = 12
    static let sessionMargin: CGFloat = 20
    static let horizontalMargin: CGFloat = 24
    static let buttonHeight: CGFloat = 56
    static let compactButtonHeight: CGFloat = 44
}

/// Chip / tag look, shared by "Last Used", "N saved", privacy note and similar labels.
extension GoPhotoDesign {
    static let tagBackground = primarySubtle
    /// Darker purple for text on `primarySubtle` (8.6:1).
    static let tagText = primaryPressed
}

// MARK: - Shared surfaces

extension View {
    /// Card surface: white with a neutral border, or `primarySubtle` with a purple border when selected.
    func goPhotoCard(
        isSelected: Bool = false,
        fill: Color? = nil,
        cornerRadius: CGFloat = GoPhotoDesign.cardCornerRadius
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(fill ?? (isSelected ? GoPhotoDesign.primarySubtle : GoPhotoDesign.surface), in: shape)
            .overlay(shape.strokeBorder(isSelected ? GoPhotoDesign.primary : GoPhotoDesign.border,
                                        lineWidth: isSelected ? 1.5 : 1))
            .contentShape(shape)
    }

    /// Tag / chip look ("Last Used", "3 saved").
    func goPhotoTag() -> some View {
        self
            .font(GoPhotoDesign.smallLabel)
            .foregroundStyle(GoPhotoDesign.tagText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(GoPhotoDesign.tagBackground, in: Capsule())
    }
}
