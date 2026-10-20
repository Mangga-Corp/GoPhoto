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
    var assetID: String?
    var cancelLoad: (() -> Void)?

    /// Editor "Select" mode: every photo shows a circle (like Photos); `isChecked` fills it.
    var selectMode = false { didSet { refresh() } }
    var isChecked = false { didSet { refresh() } }
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
        [imageView, badge].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; contentView.addSubview($0) }
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
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
