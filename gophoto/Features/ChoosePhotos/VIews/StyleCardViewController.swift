//
//  StyleCardViewController.swift
//  gophoto
//
//  "Your style" card, shown after a preset is analysed (onboarding, a new preset, or edited
//  photos): the style name, up to three traits with their photo counts, and three photos.
//

import UIKit

final class StyleCardViewController: UIViewController {
    var onDone: (() -> Void)?

    private let summary: StyleSummary
    private let presetName: String
    private let buttonTitle: String
    private var revealViews: [UIView] = []
    private var didReveal = false

    init(summary: StyleSummary, presetName: String, buttonTitle: String = "Start shooting") {
        self.summary = summary
        self.presetName = presetName
        self.buttonTitle = buttonTitle
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let kicker = UILabel.make("YOUR STYLE", style: .footnote)
        kicker.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        kicker.textColor = Theme.accent

        let name = UILabel.make(summary.name ?? "Your style, decoded", style: .largeTitle)
        name.font = .preferredFont(forTextStyle: .largeTitle).withWeight(.bold)

        var header: [UIView] = [kicker, name]
        if let tagline = summary.tagline {
            let label = UILabel.make(tagline, style: .body)
            label.textColor = Theme.text.withAlphaComponent(0.75)
            header.append(label)
        }
        let based = UILabel.make("Based on \(summary.photoCount) photos · \(presetName)", style: .footnote)
        based.textColor = Theme.text.withAlphaComponent(0.6)
        header.append(based)

        let headerStack = UIStackView(arrangedSubviews: header)
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.alignment = .center

        let traitViews = summary.traits.map(makeTraitRow)
        let traitStack = UIStackView(arrangedSubviews: traitViews)
        traitStack.axis = .vertical
        traitStack.spacing = 10

        let photos = UIStackView(arrangedSubviews: summary.highlights.map(makeThumbnail))
        photos.spacing = 10
        photos.distribution = .fillEqually

        let button = PillButton(title: buttonTitle, prominent: true)
        button.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [headerStack, traitStack, photos])
        content.axis = .vertical
        content.spacing = 24
        content.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(content)
        view.addSubview(scroll)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -12),

            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 40),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),

            button.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            button.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16)
        ])

        // Revealed one after another: name, then each trait, then the photos.
        revealViews = [headerStack] + traitViews + [photos]
        if !UIAccessibility.isReduceMotionEnabled {
            revealViews.forEach { $0.alpha = 0; $0.transform = CGAffineTransform(translationX: 0, y: 12) }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didReveal, !UIAccessibility.isReduceMotionEnabled else { return }
        didReveal = true
        for (index, view) in revealViews.enumerated() {
            UIView.animate(withDuration: 0.45, delay: 0.15 + Double(index) * 0.18,
                           usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [],
                           animations: {
                view.alpha = 1
                view.transform = .identity
            })
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func makeTraitRow(_ trait: StyleSummary.Trait) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: trait.symbol))
        icon.tintColor = Theme.accent
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let title = UILabel.make(trait.title, style: .headline)
        let line = UILabel.make(trait.line, style: .subheadline)
        line.textColor = Theme.text.withAlphaComponent(0.75)
        var texts: [UIView] = [title, line]
        if let evidence = trait.evidence {
            let label = UILabel.make(evidence, style: .footnote)
            label.textColor = Theme.accent
            texts.append(label)
        }
        for case let label as UILabel in texts { label.textAlignment = .natural }
        let textStack = UIStackView(arrangedSubviews: texts)
        textStack.axis = .vertical
        textStack.spacing = 2

        let row = UIStackView(arrangedSubviews: [icon, textStack])
        row.spacing = 14
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        row.backgroundColor = Theme.surface
        row.layer.cornerRadius = 14

        row.isAccessibilityElement = true
        row.accessibilityLabel = [trait.title, trait.line, trait.evidence].compactMap { $0 }.joined(separator: ". ")
        return row
    }

    private func makeThumbnail(_ image: UIImage) -> UIView {
        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.layer.cornerRadius = 12
        view.isAccessibilityElement = false
        view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 4.0 / 3.0).isActive = true
        return view
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: 0)
    }
}
