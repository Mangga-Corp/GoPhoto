//
//  AppFont.swift
//  gophoto
//
//  THE place to change the app's font. Every screen asks for its font through `AppFont`
//  (SwiftUI) or `UIFont.app(...)` (UIKit), so changing `AppFont.family` below swaps the font
//  everywhere.
//
//  To use another font:
//  1. Put its .ttf / .otf files in `gophoto/Resource/Fonts/` (Xcode picks them up automatically).
//  2. Set `AppFont.family` to the family name as Font Book shows it (e.g. "Alegreya Sans").
//  3. Optionally tune `AppFont.sizeBoost` (this font runs a little small next to San Francisco).
//
//  Bundled: Alegreya Sans (Light, Regular, Italic, Medium, Bold, ExtraBold), SIL Open Font License
//  (Resource/Fonts/OFL.txt).
//

import SwiftUI
import UIKit
import CoreText

enum AppFont {
    /// ⬇️ CHANGE THE FONT HERE ⬇️
    static let family = "Alegreya Sans"

    /// Added to every size: Alegreya Sans has a small x-height, so it is nudged up a little.
    /// Set to 0 for the same sizes as the system font.
    static let sizeBoost: CGFloat = 1.5

    /// Registers the bundled font files. Called once at launch (`MyApp.init`); no Info.plist entry needed.
    static func register() {
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: "Fonts") ?? [])
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    // MARK: SwiftUI text styles (same names as the system ones; they still scale with Dynamic Type)

    static let largeTitle = style(34, .largeTitle)
    static let title = style(28, .title)
    static let title2 = style(22, .title2)
    static let title3 = style(20, .title3)
    static let headline = style(17, .headline).weight(.semibold)
    static let body = style(17, .body)
    static let callout = style(16, .callout)
    static let subheadline = style(15, .subheadline)
    static let footnote = style(13, .footnote)
    static let caption = style(12, .caption)
    static let caption2 = style(11, .caption2)

    private static func style(_ size: CGFloat, _ textStyle: Font.TextStyle) -> Font {
        .custom(family, size: size + sizeBoost, relativeTo: textStyle)
    }

    /// Fixed size (does not scale), like `Font.system(size:weight:)`.
    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .custom(family, fixedSize: size + sizeBoost).weight(weight)
    }

    /// Text style with a weight, like `Font.system(_:design:weight:)`.
    static func system(_ textStyle: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight = .regular) -> Font {
        let base: CGFloat
        switch textStyle {
        case .largeTitle: base = 34
        case .title: base = 28
        case .title2: base = 22
        case .title3: base = 20
        case .headline: base = 17
        case .body: base = 17
        case .callout: base = 16
        case .subheadline: base = 15
        case .footnote: base = 13
        case .caption: base = 12
        case .caption2: base = 11
        @unknown default: base = 17
        }
        return .custom(family, size: base + sizeBoost, relativeTo: textStyle).weight(weight)
    }
}

extension UIFont {
    /// UIKit text style in the app font (scales with Dynamic Type).
    static func app(style: UIFont.TextStyle, weight: UIFont.Weight = .regular) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: style).pointSize
        return UIFontMetrics(forTextStyle: style).scaledFont(for: make(size: size + AppFont.sizeBoost, weight: weight))
    }

    /// UIKit fixed size in the app font.
    static func app(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        make(size: size + AppFont.sizeBoost, weight: weight)
    }

    private static func make(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let descriptor = UIFontDescriptor(fontAttributes: [
            .family: AppFont.family,
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}
