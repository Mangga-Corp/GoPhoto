//
//  PreferenceCell.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

/// One row in the preferences popover. When selected, shows a checkmark, an Edit button and a
/// shot-size switch (Full / 3/4 / Half / 1/4, only the sizes the preset has photos of).
final class PreferenceCell: UITableViewCell {
    static let reuseID = "PreferenceCell"
    var onEdit: (() -> Void)?
    /// Called with the picked `PresetAnalysis.ShotSize.rawValue` when the switch changes.
    var onFraming: ((String) -> Void)?

    /// The shot sizes shown, in segment order (`ShotSize.rawValue`).
    private var framings: [String] = []
    private let framingControl = UISegmentedControl(items: [])

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
            guard let self, self.framings.indices.contains(self.framingControl.selectedSegmentIndex) else { return }
            self.onFraming?(self.framings[self.framingControl.selectedSegmentIndex])
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

    /// `shots`: the shot sizes the preset has photos of (`ShotSize.rawValue`, widest first);
    /// the switch is hidden without any. `framing`: the one in use, or nil when unknown.
    func configure(name: String, selected: Bool, framing: String? = nil, shots: [String] = []) {
        nameLabel.text = name
        nameLabel.accessibilityValue = selected ? "Selected" : nil
        checkmark.isHidden = !selected
        editRow.isHidden = !selected
        if shots != framings {
            framings = shots
            framingControl.removeAllSegments()
            for (index, raw) in shots.enumerated() {
                let shot = PresetAnalysis.ShotSize(rawValue: raw)
                framingControl.insertSegment(withTitle: shot?.shortTitle ?? raw, at: index, animated: false)
            }
        }
        framingControl.isHidden = shots.isEmpty
        framingControl.selectedSegmentIndex = framing.flatMap { framings.firstIndex(of: $0) }
            ?? UISegmentedControl.noSegment
    }
}
