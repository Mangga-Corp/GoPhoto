//
//  CircleButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// Round button with a text glyph ("X", "+").
final class CircleButton: UIButton {
    init(title: String, accessibilityLabel label: String) {
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        setTitleColor(Theme.text, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 22)
        backgroundColor = Theme.surface
        layer.borderWidth = 1
        accessibilityLabel = label
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.borderColor = Theme.stroke.cgColor
    }
}
