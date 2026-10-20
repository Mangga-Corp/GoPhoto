//
//  PillButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// Text button ("Select", "Done", "Add", "Edit").
/// System Liquid Glass on iOS 26, system gray/filled before that. Always at least 44 pt tall.
/// Use `prominent` only for the single most likely action in a view.
final class PillButton: UIButton {
    init(title: String, prominent: Bool = false) {
        super.init(frame: .zero)
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = prominent ? .prominentGlass() : .glass()
        } else {
            configuration = prominent ? .filled() : .gray()
        }
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.preferredFont(forTextStyle: .body)
            return attributes
        }
        if prominent {
            configuration.baseBackgroundColor = Theme.accent
            configuration.baseForegroundColor = Theme.onAccent
            tintColor = Theme.accent
        } else {
            configuration.baseForegroundColor = Theme.text
        }
        self.configuration = configuration
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateTitle(_ title: String) { configuration?.title = title }

    /// Shows the system activity indicator inside the button (for actions that don't finish instantly).
    func setLoading(_ loading: Bool) { configuration?.showsActivityIndicator = loading }
}
