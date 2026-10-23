//
//  PreferenceCell.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// One row in the preferences popover. When selected, shows a checkmark, an Edit button and a
/// Full / Half body switch below the name.
final class PreferenceCell: UITableViewCell {
    static let reuseID = "PreferenceCell"
    var onEdit: (() -> Void)?
    /// Called with "fullBody" / "halfBody" when the framing switch changes.
    var onFraming: ((String) -> Void)?

    static let framings = ["fullBody", "halfBody"]
    private let framingControl = UISegmentedControl(items: ["Full body", "Half body"])

    private let nameLabel = UILabel.make("", style: .body)
    private let checkmark = UIImageView(image: UIImage(systemName: "checkmark"))
    private let editRow: UIStackView

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        let editButton = PillButton(title: "Edit")
        editRow = UIStackView(arrangedSubviews: [editButton, UIView(), framingControl])
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        editButton.addAction(UIAction { [weak self] _ in self?.onEdit?() }, for: .touchUpInside)
        editRow.alignment = .center
        editRow.spacing = 8
        framingControl.addAction(UIAction { [weak self] _ in
            guard let self, Self.framings.indices.contains(self.framingControl.selectedSegmentIndex) else { return }
            self.onFraming?(Self.framings[self.framingControl.selectedSegmentIndex])
        }, for: .valueChanged)

        backgroundColor = .clear
        selectionStyle = .none
        nameLabel.textAlignment = .natural
        checkmark.tintColor = Theme.accent
        checkmark.isAccessibilityElement = false
        checkmark.setContentHuggingPriority(.required, for: .horizontal)

        let top = UIStackView(arrangedSubviews: [nameLabel, checkmark])
        top.spacing = 8
        top.alignment = .center
        let stack = UIStackView(arrangedSubviews: [top, editRow])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// `framing`: the framing in use ("fullBody" / "halfBody"), or nil when unknown.
    func configure(name: String, selected: Bool, framing: String? = nil) {
        nameLabel.text = name
        nameLabel.accessibilityValue = selected ? "Selected" : nil
        checkmark.isHidden = !selected
        editRow.isHidden = !selected
        framingControl.selectedSegmentIndex = framing.flatMap { Self.framings.firstIndex(of: $0) }
            ?? UISegmentedControl.noSegment
    }
}
