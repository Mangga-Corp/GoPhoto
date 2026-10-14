//
//  AIPreferencesViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

final class AIPreferencesViewController: UIViewController {
    /// Called when the back button (top-left) is tapped.
    var onBack: (() -> Void)?

    private let viewModel: ChoosePhotosViewModel

    private let titleLabel = UILabel.make("AI Preferences", style: .title3)
    private let subtitleLabel = UILabel.make("", style: .footnote)
    private let emptyLabel = UILabel.make("You haven’t input any photo", style: .subheadline)
    private let editButton = PillButton(title: "Edit")
    private let addButton = CircleButton(title: "+", accessibilityLabel: "Add photos")
    private let backButton: UIButton = {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "chevron.left")
        configuration.baseForegroundColor = Theme.text
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = "Back"
        return button
    }()
    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.25)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 120, trailing: 10)
        return UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
    }()

    init(viewModel: ChoosePhotosViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)

        viewModel.onItemsChange = { [weak self] in self?.renderItems() }
        viewModel.onEditingChange = { [weak self] in self?.renderEditing() }
        backButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        editButton.addAction(UIAction { [weak self] _ in self?.viewModel.toggleEditing() }, for: .touchUpInside)
        addButton.addAction(UIAction { [weak self] _ in self?.addTapped() }, for: .touchUpInside)

        [collectionView, titleLabel, subtitleLabel, backButton, editButton, emptyLabel, addButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: safe.topAnchor, constant: 24),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            backButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            editButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            editButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collectionView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            addButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            addButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            addButton.widthAnchor.constraint(equalToConstant: 52),
            addButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        renderItems()
    }

    // MARK: - Render

    private func renderItems() {
        emptyLabel.isHidden = viewModel.hasItems
        collectionView.isHidden = !viewModel.hasItems
        subtitleLabel.text = viewModel.subtitleText
        collectionView.reloadData()
    }

    private func renderEditing() {
        editButton.updateTitle(viewModel.editButtonTitle)
        collectionView.visibleCells.compactMap { $0 as? PhotoCell }.forEach { $0.removeMode = viewModel.isEditing }
    }

    // MARK: - Navigation

    private func addTapped() {
        switch viewModel.addTapped() {
        case .limitReached: showAlert(message: viewModel.limitMessage)
        case .permission: requestAccessThenPick()
        case .picker: presentPicker()
        case .settings: showSettingsAlert()
        }
    }

    private func requestAccessThenPick() {
        viewModel.requestAccess { [weak self] canBrowse in
            if canBrowse { self?.presentPicker() }
        }
    }

    private func presentPicker() {
        let vc = SelectPhotoViewController(viewModel: viewModel.makePickerViewModel())
        vc.onCancel = { [weak self] in self?.dismiss(animated: true) }
        vc.onDone = { [weak self] newItems in
            self?.viewModel.append(newItems)
            self?.dismiss(animated: true)
        }
        present(vc, animated: true)
    }

    private func showAlert(message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    private func showSettingsAlert() {
        let a = UIAlertController(title: "Photo Access Needed",
                                  message: "Allow photo access in Settings to choose photos.", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        present(a, animated: true)
    }
}

extension AIPreferencesViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { viewModel.items.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        guard let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as? PhotoCell
        else { return UICollectionViewCell() }
        cell.imageView.image = viewModel.items[ip.item].image
        cell.removeMode = viewModel.isEditing
        return cell
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        guard viewModel.isEditing else { return }
        viewModel.remove(at: ip.item)
    }
}
