//
//  SelectPhotoViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import UIKit
import Photos
import PhotosUI

final class SelectPhotoViewController: UIViewController {
    var onCancel: (() -> Void)?
    var onDone: (([PhotoItem]) -> Void)?

    private let viewModel: SelectPhotoViewModel
    private let closeButton = CircleButton(symbol: "xmark", accessibilityLabel: "Close")
    private let doneButton = PillButton(title: "Done", prominent: true)
    private lazy var selectPan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSelectPan(_:)))
        pan.delegate = self
        return pan
    }()
    private var panStartIndex: Int?
    private var panSelects = true
    private var panInitialSelection: Set<Int> = []
    private var panLastRange: ClosedRange<Int>?
    private var panHitLimit = false
    private let selectionHaptic = UISelectionFeedbackGenerator()
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
        overrideUserInterfaceStyle = .light
        view.backgroundColor = Theme.background

        let title = UILabel.make("Select Photo", style: .headline)
        collectionView.backgroundColor = .clear
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        collectionView.addGestureRecognizer(selectPan)
        collectionView.panGestureRecognizer.require(toFail: selectPan)
        viewModel.onLoadingChange = { [weak self] on in self?.setLoading(on) }
        viewModel.onError = { [weak self] message in self?.showError(message) }
        viewModel.onFinish = { [weak self] items in self?.onDone?(items) }
        closeButton.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        doneButton.addAction(UIAction { [weak self] _ in self?.doneTapped() }, for: .touchUpInside)

        [collectionView, closeButton, title, doneButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0)
        }
        var gridTopAnchor = closeButton.bottomAnchor
        if viewModel.isLimitedAccess {
            let banner = makeLimitedAccessBanner()
            banner.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 12),
                banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                banner.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            ])
            gridTopAnchor = banner.bottomAnchor
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
            collectionView.topAnchor.constraint(equalTo: gridTopAnchor, constant: 16),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func doneTapped() {
        viewModel.done(selectedIndexes: (collectionView.indexPathsForSelectedItems ?? []).map(\.item))
    }

    private func setLoading(_ on: Bool) {
        doneButton.setLoading(on)
        view.isUserInteractionEnabled = !on
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    private func makeLimitedAccessBanner() -> UIView {
        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.tintColor = Theme.accent
        icon.contentMode = .center
        icon.backgroundColor = .white
        icon.layer.cornerRadius = 10
        icon.clipsToBounds = true
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
        ])

        let message = NSMutableAttributedString(
            string: "You've limited access to selected items. ",
            attributes: [.font: UIFont.systemFont(ofSize: 15), .foregroundColor: Theme.text])
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            message.append(NSAttributedString(
                string: "Settings",
                attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .link: settingsURL]))
        }

        let text = UITextView()
        text.attributedText = message
        text.linkTextAttributes = [.foregroundColor: Theme.accent]
        text.isEditable = false
        text.isScrollEnabled = false
        text.backgroundColor = .clear
        text.textContainerInset = .zero
        text.textContainer.lineFragmentPadding = 0

        var config = UIButton.Configuration.filled()
        config.title = "Add more"
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        let addMore = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.presentLimitedPicker()
        })
        addMore.setContentHuggingPriority(.required, for: .horizontal)
        addMore.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = UIStackView(arrangedSubviews: [icon, text, addMore])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        stack.backgroundColor = Theme.tagBackground
        stack.layer.cornerRadius = 14
        return stack
    }

    private func presentLimitedPicker() {
        Task {
            _ = await PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
            limitedSelectionChanged()
        }
    }

    private func limitedSelectionChanged() {
        let selectedIDs = Set((collectionView.indexPathsForSelectedItems ?? []).map { viewModel.identifier(at: $0.item) })
        viewModel.reload()
        collectionView.reloadData()
        for index in 0..<viewModel.count where selectedIDs.contains(viewModel.identifier(at: index)) {
            collectionView.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: [])
        }
    }

    @objc private func handleSelectPan(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: collectionView)
        switch pan.state {
        case .began:
            guard let index = collectionView.indexPathForItem(at: point)?.item else { return }
            panStartIndex = index
            panInitialSelection = selectedIndexes
            panSelects = !panInitialSelection.contains(index)
            panLastRange = nil
            panHitLimit = false
            applyPanRange(to: index)
        case .changed:
            guard panStartIndex != nil,
                  let index = collectionView.indexPathForItem(at: point)?.item else { return }
            applyPanRange(to: index)
        default:
            panStartIndex = nil
            panLastRange = nil
        }
    }

    private var selectedIndexes: Set<Int> {
        Set((collectionView.indexPathsForSelectedItems ?? []).map(\.item))
    }

    private func applyPanRange(to index: Int) {
        guard let start = panStartIndex else { return }
        let range = min(start, index)...max(start, index)
        guard range != panLastRange else { return }
        let touched = Set(range).union(panLastRange.map { Set($0) } ?? [])
        for item in touched.sorted() {
            let shouldSelect = range.contains(item) ? panSelects : panInitialSelection.contains(item)
            setSelected(shouldSelect, at: item)
        }
        panLastRange = range
        selectionHaptic.selectionChanged()
    }

    private func setSelected(_ selected: Bool, at item: Int) {
        let indexPath = IndexPath(item: item, section: 0)
        guard selected != selectedIndexes.contains(item) else { return }
        if selected {
            guard viewModel.hasRoom(currentCount: selectedIndexes.count) else {
                if !panHitLimit {
                    panHitLimit = true
                    _ = viewModel.canSelect(currentCount: selectedIndexes.count)
                }
                return
            }
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
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

extension SelectPhotoViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === selectPan else { return true }
        let velocity = selectPan.velocity(in: collectionView)
        return abs(velocity.x) > abs(velocity.y)
    }
}
