//
//  PhotoCell.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

final class PhotoCell: UICollectionViewCell {
    static let reuseID = "PhotoCell"
    let imageView = UIImageView()
    private let badge = UIImageView()
    private let postureBadge = UIImageView(image: UIImage(systemName: "figure.seated.side"))
    var assetID: String?
    var cancelLoad: (() -> Void)?

    /// Editor "Select" mode: every photo shows a circle (like Photos); `isChecked` fills it.
    var selectMode = false { didSet { refresh() } }
    var isChecked = false { didSet { refresh() } }
    /// Small seated glyph in the corner for photos of a seated person.
    var isSeated = false { didSet { postureBadge.isHidden = !isSeated } }
    /// Used by the photo picker (system multi-selection).
    override var isSelected: Bool { didSet { refresh() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 4
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        badge.backgroundColor = Theme.surface
        badge.layer.cornerRadius = 11
        postureBadge.tintColor = Theme.text
        postureBadge.backgroundColor = Theme.surface.withAlphaComponent(0.9)
        postureBadge.contentMode = .center
        postureBadge.layer.cornerRadius = 11
        postureBadge.clipsToBounds = true
        postureBadge.isHidden = true
        [imageView, badge, postureBadge].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            postureBadge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            postureBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            postureBadge.widthAnchor.constraint(equalToConstant: 22),
            postureBadge.heightAnchor.constraint(equalToConstant: 22),
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22)
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Photo"
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelLoad?(); cancelLoad = nil
        imageView.image = nil
        isSeated = false
        assetID = nil
    }

    private func refresh() {
        let picked = selectMode ? isChecked : isSelected
        badge.isHidden = !(selectMode || isSelected)
        badge.image = UIImage(systemName: picked ? "checkmark.circle.fill" : "circle")
        badge.tintColor = picked ? Theme.accent : Theme.text.withAlphaComponent(0.5)
        contentView.layer.borderWidth = picked ? 3 : 1
        contentView.layer.borderColor = (picked ? Theme.accent : Theme.stroke).cgColor
        accessibilityTraits = picked ? [.button, .selected] : .button
    }
}
