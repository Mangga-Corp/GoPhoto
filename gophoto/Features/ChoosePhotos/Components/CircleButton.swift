//
//  CircleButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// Round icon button (SF Symbol). Liquid Glass on iOS 26, system gray before that. At least 44 x 44 pt.
/// Pass `tint: .systemRed` for destructive actions.
final class CircleButton: UIButton {
    init(symbol: String, accessibilityLabel label: String, tint: UIColor? = nil) {
        super.init(frame: .zero)
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.image = UIImage(systemName: symbol)
        configuration.cornerStyle = .capsule
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        configuration.baseForegroundColor = tint ?? Theme.text
        self.configuration = configuration
        accessibilityLabel = label
        widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
