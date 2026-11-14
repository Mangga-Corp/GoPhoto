//
//  StyleCardViewController.swift
//  gophoto
//
//  "Your style" card, shown after a preset is analysed (onboarding, a new preset, or edited
//  photos): the style name and up to three traits with their photo counts.
//

import SwiftUI
import UIKit

final class StyleCardViewController: UIViewController {
    var onDone: (() -> Void)?

    private let summary: StyleSummary
    private let buttonTitle: String
    private var revealViews: [UIView] = []
    private var didReveal = false

    /// `buttonTitle`: "Open Camera" when the button starts the session (onboarding, a new
    /// preference), "Done" after editing photos.
    init(summary: StyleSummary, buttonTitle: String = "Open Camera") {
        self.summary = summary
        self.buttonTitle = buttonTitle
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .light
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let background = UIColor(GoPhotoDesign.background)
        let primaryText = UIColor(GoPhotoDesign.primaryText)
        let secondaryText = UIColor(GoPhotoDesign.secondaryText)
        let accent = UIColor(GoPhotoDesign.primary)
        overrideUserInterfaceStyle = .light
        view.backgroundColor = background

        let kicker = UILabel.make("YOUR STYLE", style: .footnote)
        kicker.font = .app(style: .footnote, weight: .semibold)
        kicker.textColor = accent

        var header: [UIView] = [kicker]
        if let name = summary.name {
            let label = UILabel.make(name, style: .largeTitle)
            label.font = .app(style: .largeTitle, weight: .bold)
            label.textColor = primaryText
            header.append(label)
        }
        if let tagline = summary.tagline {
            let label = UILabel.make(tagline, style: .body)
            label.textColor = secondaryText
            header.append(label)
        }
        let count = summary.photoCount
        let based = UILabel.make("Based on \(count) \(count == 1 ? "photo" : "photos")", style: .footnote)
        based.textColor = secondaryText
        header.append(based)

        let headerStack = UIStackView(arrangedSubviews: header)
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.alignment = .center

        let traitViews = summary.traits.map(makeTraitRow)
        let traitStack = UIStackView(arrangedSubviews: traitViews)
        traitStack.axis = .vertical
        traitStack.spacing = 12

        let button = PillButton(title: buttonTitle, prominent: true, fullWidthHeight: true)
        button.addAction(UIAction { [weak self] _ in self?.onDone?() }, for: .touchUpInside)

        let content = UIStackView(arrangedSubviews: [headerStack, traitStack])
        content.axis = .vertical
        content.spacing = 32
        content.translatesAutoresizingMaskIntoConstraints = false

        // Header and cards as one group, centred (a little above centre) in the space above the
        // button; when they don't fit (large text) they start at the top and scroll.
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.addSubview(container)
        view.addSubview(scroll)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        let centered = content.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24)
        centered.priority = .defaultHigh
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: safe.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: button.topAnchor, constant: -12),

            container.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            container.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),

            centered,
            content.topAnchor.constraint(greaterThanOrEqualTo: container.topAnchor, constant: 32),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            button.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            button.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            button.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -16)
        ])
        button.accessibilityIdentifier = "styleCard.primary"

        // Revealed one after another: name, then each trait.
        revealViews = [headerStack] + traitViews
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
        icon.tintColor = UIColor(GoPhotoDesign.primary)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
        icon.contentMode = .scaleAspectFit
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true

        let title = UILabel.make(trait.title, style: .headline)
        title.textColor = UIColor(GoPhotoDesign.primaryText)
        let line = UILabel.make(trait.line, style: .subheadline)
        line.textColor = UIColor(GoPhotoDesign.secondaryText)
        var texts: [UIView] = [title, line]
        if let evidence = trait.evidence {
            let label = UILabel.make(evidence, style: .footnote)
            label.textColor = UIColor(GoPhotoDesign.primary)
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
        row.backgroundColor = UIColor(GoPhotoDesign.primarySubtle)
        row.layer.cornerRadius = GoPhotoDesign.cardCornerRadius

        row.isAccessibilityElement = true
        row.accessibilityLabel = [trait.title, trait.line, trait.evidence].compactMap { $0 }.joined(separator: ". ")
        return row
    }

}

