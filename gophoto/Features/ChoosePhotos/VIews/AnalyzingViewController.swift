//
//  AnalyzingViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import UIKit

final class AnalyzingViewController: UIViewController {
    var onFinish: (() -> Void)?

    private let viewModel: AnalyzingViewModel
    private let photos: [PhotoItem]
    private var thumbnails: [UIImageView] = []
    private var didStart = false

    private let iconView = UIImageView(image: UIImage(systemName: "sparkles"))
    private let titleLabel = UILabel.make("Analyzing your photos", style: .title3)
    private let messageLabel = UILabel.make("", style: .subheadline)

    init(viewModel: AnalyzingViewModel, photos: [PhotoItem]) {
        self.viewModel = viewModel
        self.photos = photos
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        iconView.tintColor = Theme.accent
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
        iconView.isAccessibilityElement = false
        messageLabel.text = viewModel.initialMessage

        thumbnails = photos.prefix(4).map { item in
            let v = UIImageView(image: item.image)
            v.contentMode = .scaleAspectFill
            v.clipsToBounds = true
            v.layer.cornerRadius = 8
            v.isAccessibilityElement = false
            v.widthAnchor.constraint(equalToConstant: 64).isActive = true
            v.heightAnchor.constraint(equalToConstant: 64).isActive = true
            return v
        }
        let row = UIStackView(arrangedSubviews: thumbnails)
        row.spacing = 10
        row.alignment = .center

        let stack = UIStackView(arrangedSubviews: [iconView, row, titleLabel, messageLabel])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -32)
        ])

        viewModel.onMessage = { [weak self] message in self?.show(message) }
        viewModel.onFinish = { [weak self] in self?.onFinish?() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didStart else { return }
        didStart = true
        startAnimations()
        viewModel.start(with: photos)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cancel()
    }

    private func startAnimations() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        iconView.addSymbolEffect(.pulse, options: .repeating)
        for (index, thumbnail) in thumbnails.enumerated() {
            UIView.animate(withDuration: 0.7, delay: Double(index) * 0.25,
                           options: [.repeat, .autoreverse, .curveEaseInOut]) { thumbnail.alpha = 0.35 }
        }
    }

    private func show(_ message: String) {
        UIView.transition(with: messageLabel, duration: 0.3, options: .transitionCrossDissolve) {
            self.messageLabel.text = message
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}
