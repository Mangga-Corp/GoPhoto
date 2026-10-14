//
//  SelectPhotoViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit

final class SelectPhotoViewController: UIViewController {
    var onCancel: (() -> Void)?
    var onDone: (([PhotoItem]) -> Void)?

    private let viewModel: SelectPhotoViewModel
    private let closeButton = CircleButton(title: "X", accessibilityLabel: "Close")
    private let doneButton = PillButton(title: "Done")
    private let spinner = UIActivityIndicatorView(style: .large)
    private lazy var collectionView: UICollectionView = {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1)))
        item.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.25)), subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 12, trailing: 12)
        return UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewCompositionalLayout(section: section))
    }()

    init(viewModel: SelectPhotoViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let title = UILabel.make("Select Photo", style: .headline)
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        spinner.color = Theme.text

        viewModel.onLoadingChange = { [weak self] on in self?.setLoading(on) }
        viewModel.onError = { [weak self] message in self?.showError(message) }
        viewModel.onFinish = { [weak self] items in self?.onDone?(items) }
        closeButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self] _ in self?.doneTapped() }, for: .touchUpInside)

        [collectionView, closeButton, title, doneButton, spinner].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            closeButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            doneButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            collectionView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func doneTapped() {
        viewModel.done(selectedIndexes: (collectionView.indexPathsForSelectedItems ?? []).map(\.item))
    }

    private func setLoading(_ on: Bool) {
        on ? spinner.startAnimating() : spinner.stopAnimating()
        view.isUserInteractionEnabled = !on
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension SelectPhotoViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int { viewModel.count }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        guard let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as? PhotoCell
        else { return UICollectionViewCell() }
        let id = viewModel.identifier(at: ip.item)
        cell.assetID = id
        cell.cancelLoad = viewModel.loadThumbnail(at: ip.item, side: 120 * traitCollection.displayScale) { [weak cell] image in
            guard cell?.assetID == id else { return }
            cell?.imageView.image = image
        }
        return cell
    }

    func collectionView(_ cv: UICollectionView, shouldSelectItemAt ip: IndexPath) -> Bool {
        viewModel.canSelect(currentCount: cv.indexPathsForSelectedItems?.count ?? 0)
    }
}
