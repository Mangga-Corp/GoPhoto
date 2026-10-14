//
//  PillButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// Rounded pill button ("Edit", "Done", "Allow", "Dont Allow").
final class PillButton: UIButton {
    init(title: String) {
        super.init(frame: .zero)
        var c = UIButton.Configuration.plain()
        c.title = title
        c.baseForegroundColor = Theme.text
        c.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 22, bottom: 10, trailing: 22)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var a = $0; a.font = UIFont.preferredFont(forTextStyle: .subheadline); return a
        }
        configuration = c
        backgroundColor = Theme.surface
        layer.borderWidth = 1
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateTitle(_ title: String) { configuration?.title = title }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.borderColor = Theme.stroke.cgColor
    }
}
