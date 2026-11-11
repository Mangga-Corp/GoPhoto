//
//  CircleButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// Round icon button (SF Symbol). Liquid Glass on iOS 26, system gray before that. At least 44 x 44 pt.
/// Pass `tint: Theme.destructive` for destructive actions, or `prominent: true` for primary purple background.
final class CircleButton: UIButton {
    init(symbol: String, accessibilityLabel label: String, tint: UIColor? = nil, prominent: Bool = false) {
        super.init(frame: .zero)
        var configuration: UIButton.Configuration
        if prominent {
            configuration = .filled()
            configuration.baseBackgroundColor = Theme.accent
            configuration.baseForegroundColor = Theme.onAccent
        } else if #available(iOS 26, *) {
            configuration = .glass()
            configuration.baseForegroundColor = tint ?? Theme.text
        } else {
            configuration = .gray()
            configuration.baseForegroundColor = tint ?? Theme.text
        }
        configuration.image = UIImage(systemName: symbol)
        configuration.cornerStyle = .capsule
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        self.configuration = configuration
        accessibilityLabel = label

        if prominent {
            configurationUpdateHandler = { button in
                var updated = button.configuration
                if !button.isEnabled {
                    updated?.baseBackgroundColor = Theme.accent.withAlphaComponent(0.4)
                    updated?.baseForegroundColor = Theme.onAccent.withAlphaComponent(0.6)
                } else {
                    updated?.baseBackgroundColor = button.isHighlighted ? Theme.accentPressed : Theme.accent
                    updated?.baseForegroundColor = Theme.onAccent
                }
                button.configuration = updated
            }
        }

        widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
