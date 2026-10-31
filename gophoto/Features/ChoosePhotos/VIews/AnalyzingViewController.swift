//
//  AnalyzingViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 14/10/26.
//

import SwiftUI
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
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let progressLabel = UILabel.make("0%", style: .subheadline)
    private var progressFillWidth: NSLayoutConstraint!
    private var displayedProgress = 0.0

    init(viewModel: AnalyzingViewModel, photos: [PhotoItem]) {
        self.viewModel = viewModel
        self.photos = photos
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = UIColor(GoPhotoDesign.background)

        iconView.tintColor = UIColor(GoPhotoDesign.purple)
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40)
        iconView.isAccessibilityElement = false
        titleLabel.textColor = UIColor(GoPhotoDesign.primaryText)
        messageLabel.text = viewModel.initialMessage
        messageLabel.textColor = UIColor(GoPhotoDesign.secondaryText)

        progressTrack.backgroundColor = UIColor(GoPhotoDesign.purple).withAlphaComponent(0.2)
        progressTrack.layer.cornerRadius = 4
        progressTrack.clipsToBounds = true
        progressFill.backgroundColor = UIColor(GoPhotoDesign.purple)
        progressFill.layer.cornerRadius = 4
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)
        progressFillWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressFillWidth
        ])
        progressLabel.textColor = UIColor(GoPhotoDesign.secondaryText)
        progressLabel.textAlignment = .center
        progressLabel.font = messageLabel.font
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.translatesAutoresizingMaskIntoConstraints = false

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
        view.addSubview(progressTrack)
        view.addSubview(progressLabel)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -32),
            progressTrack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20),
            progressTrack.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            progressTrack.widthAnchor.constraint(equalToConstant: 220),
            progressTrack.heightAnchor.constraint(equalToConstant: 8),
            progressLabel.topAnchor.constraint(equalTo: progressTrack.bottomAnchor, constant: 8),
            progressLabel.centerXAnchor.constraint(equalTo: progressTrack.centerXAnchor)
        ])

        viewModel.onMessage = { [weak self] message in self?.show(message) }
        viewModel.onProgress = { [weak self] progress in self?.updateProgress(progress) }
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

    private func updateProgress(_ progress: Double) {
        guard progress >= displayedProgress else { return }
        displayedProgress = progress
        progressLabel.text = "\(Int((progress * 100).rounded()))%"
        view.layoutIfNeeded()
        progressFillWidth.constant = progressTrack.bounds.width * CGFloat(progress)
        UIView.animate(
            withDuration: 0.08,
            delay: 0,
            options: [.beginFromCurrentState, .curveLinear]
        ) {
            self.view.layoutIfNeeded()
        }
    }
}
