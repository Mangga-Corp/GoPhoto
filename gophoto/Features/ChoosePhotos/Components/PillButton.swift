//
//  PillButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// Text button ("Select", "Done", "Add", "Edit").
/// Non-prominent: system Liquid Glass on iOS 26, system gray before that.
/// Prominent: the app's primary button (solid `Theme.accent` capsule, darker when pressed, muted
/// when disabled), matching the SwiftUI `.goPhotoPrimary` style. Use it for the single most likely
/// action in a view; `fullWidthHeight` gives it the standard 56 pt primary height.
/// Always at least 44 pt tall.
final class PillButton: UIButton {
    init(title: String, prominent: Bool = false, fullWidthHeight: Bool = false) {
        super.init(frame: .zero)
        var configuration: UIButton.Configuration
        if prominent {
            configuration = .filled()
        } else if #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        let weight: UIFont.Weight = prominent ? .semibold : .regular
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            let base = UIFont.preferredFont(forTextStyle: .body)
            attributes.font = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
            return attributes
        }
        if prominent {
            configuration.baseBackgroundColor = Theme.accent
            configuration.baseForegroundColor = Theme.onAccent
            tintColor = Theme.accent
            configurationUpdateHandler = { button in
                var updated = button.configuration
                if !button.isEnabled {
                    updated?.baseBackgroundColor = Theme.disabledFill
                    updated?.baseForegroundColor = Theme.disabledText
                } else {
                    updated?.baseBackgroundColor = button.isHighlighted ? Theme.accentPressed : Theme.accent
                    updated?.baseForegroundColor = Theme.onAccent
                }
                button.configuration = updated
            }
        } else {
            configuration.baseForegroundColor = Theme.text
        }
        self.configuration = configuration
        let minimumHeight = prominent && fullWidthHeight ? Theme.buttonHeight : 44
        heightAnchor.constraint(greaterThanOrEqualToConstant: minimumHeight).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateTitle(_ title: String) { configuration?.title = title }

    /// Shows the system activity indicator inside the button (for actions that don't finish instantly).
    func setLoading(_ loading: Bool) { configuration?.showsActivityIndicator = loading }
}
