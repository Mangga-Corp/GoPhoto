//
//  AIPreferencesViewController.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

final class AIPreferencesViewController: UIViewController {
    /// Called when the back button (top-left) is tapped.
    var onBack: (() -> Void)?
    /// Onboarding: called after the picker closes and the user has named the preference.
    var onPhotosAdded: (([PhotoItem], String) -> Void)?
    /// The analysed framing of a photo ("fullBody" / "halfBody" / other), to group the grid into
    /// Full body / Half body sections. Nil = one plain grid (e.g. a preference being created).
    var framingOf: ((PhotoItem) -> String?)?

    private let viewModel: ChoosePhotosViewModel
    private var photoPickerFlow: PhotoPreferencePickerFlow?

    // MARK: - Navigation Bar Items

    private let backButton = CircleButton(symbol: "chevron.left", accessibilityLabel: "Back")
    private let moreButton = CircleButton(symbol: "ellipsis", accessibilityLabel: "More options")
    private let selectButton = PillButton(title: "Select")
    private let trashButton = CircleButton(symbol: "trash", accessibilityLabel: "Delete", tint: Theme.destructive)

    // MARK: - Header Elements (Left-aligned as in reference design)

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 28, weight: .bold)
        label.textColor = Theme.text
        label.textAlignment = .left
        label.numberOfLines = 1
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = Theme.text
        label.textAlignment = .left
        return label
    }()

    private let guidanceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = Theme.secondaryText
        label.text = "Clear, full-body photos work best."
        label.textAlignment = .left
        return label
    }()

    // MARK: - Privacy Banner

    private lazy var privacyBanner: UIView = {
        let icon = UIImageView(image: UIImage(systemName: "lock.shield.fill"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        icon.tintColor = Theme.accent
        icon.contentMode = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)

        let label = UILabel()
        label.text = "Your photos stay on this iPhone. They're analyzed on your device and never uploaded."
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = Theme.text
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        stack.backgroundColor = Theme.tagBackground
        stack.layer.cornerRadius = 14
        stack.layer.borderWidth = 1
        stack.layer.borderColor = Theme.accentBorder.withAlphaComponent(0.3).cgColor
        return stack
    }()

    // MARK: - Wide "+ Add photos" Button (Full width dashed box as in Image 1)

    private lazy var wideAddPhotosButton: WideAddPhotosButton = {
        let btn = WideAddPhotosButton()
        btn.addAction(UIAction { [weak self] _ in
            self?.photoPickerFlow?.start()
        }, for: .touchUpInside)
        return btn
    }()

    // MARK: - 3-Column Grid

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, _ in
            guard let self else { return nil }
            let sections = self.sections
            // 3-column grid: 1/3 width, aspect ratio 1:1
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / 3.0),
                heightDimension: .fractionalHeight(1))
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            let groupHeight = NSCollectionLayoutDimension.fractionalWidth(1.0 / 3.0)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: groupHeight),
                subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            let isLast = sectionIndex >= sections.count - 1
            section.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 13, bottom: isLast ? 40 : 16, trailing: 13)
            if sections.indices.contains(sectionIndex), sections[sectionIndex].title != nil {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(32)),
                    elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                section.boundarySupplementaryItems = [header]
            }
            return section
        }
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    // MARK: - Sections

    private var sections: [(title: String?, indices: [Int])] {
        let all = Array(viewModel.items.indices)
        guard let framingOf else { return [(nil, all)] }
        let titles = all.map { framingOf(viewModel.items[$0]).flatMap(Self.framingTitle) }
        let order = ["Full body", "Three-quarter", "Half body", "One-quarter"]
        if titles.allSatisfy({ $0 == nil }) { return [(nil, all)] }
        var groups: [(title: String?, indices: [Int])] = order.map { title in
            (title, all.filter { titles[$0] == title })
        }
        groups.append(("Other", all.filter { titles[$0] == nil }))
        return groups.filter { !$0.indices.isEmpty }
    }

    private func indexPath(forItem item: Int) -> IndexPath? {
        for (section, group) in sections.enumerated() {
            if let row = group.indices.firstIndex(of: item) { return IndexPath(item: row, section: section) }
        }
        return nil
    }

    private static func framingTitle(_ framing: String) -> String? {
        switch framing {
        case "full", "fullBody": "Full body"
        case "threeQuarter": "Three-quarter"
        case "half", "halfBody": "Half body"
        case "quarter": "One-quarter"
        default: nil
        }
    }

    private func showPhoto(at item: Int) {
        let order = sections.flatMap { $0.indices }
        guard let start = order.firstIndex(of: item) else { return }
        let images = order.map { viewModel.items[$0].image }
        let labels = order.map { index in framingOf?(viewModel.items[index]).flatMap(Self.framingTitle) }
        final class Current { var item: Int; init(_ item: Int) { self.item = item } }
        let current = Current(item)

        let pager = PreferencePhotoPager(
            images: images, labels: labels, startIndex: start,
            onPageChange: { [weak self] page in
                guard let self, order.indices.contains(page) else { return }
                current.item = order[page]
                if let ip = self.indexPath(forItem: current.item) {
                    self.collectionView.scrollToItem(at: ip, at: .centeredVertically, animated: false)
                }
            },
            onClose: { [weak self] in self?.dismiss(animated: true) })
        let host = UIHostingController(rootView: pager)
        host.modalPresentationStyle = .fullScreen
        host.preferredTransition = .zoom { [weak self] _ in
            guard let self, let ip = self.indexPath(forItem: current.item) else { return nil }
            return self.collectionView.cellForItem(at: ip)
        }
        present(host, animated: true)
    }

    private func itemIndex(at indexPath: IndexPath) -> Int? {
        let sections = self.sections
        guard sections.indices.contains(indexPath.section),
              sections[indexPath.section].indices.indices.contains(indexPath.item) else { return nil }
        return sections[indexPath.section].indices[indexPath.item]
    }

    init(viewModel: ChoosePhotosViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .light
        view.backgroundColor = Theme.background
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuseID)

        viewModel.onItemsChange = { [weak self] in self?.renderItems() }
        viewModel.onSelectionChange = { [weak self] in self?.renderSelection() }
        backButton.addAction(UIAction { [weak self] _ in self?.backTapped() }, for: .touchUpInside)
        selectButton.addAction(UIAction { [weak self] _ in self?.viewModel.toggleSelecting() }, for: .touchUpInside)
        trashButton.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .touchUpInside)

        // Menu on top right ellipsis button
        setupMoreMenu()

        photoPickerFlow = PhotoPreferencePickerFlow(
            presenter: self,
            viewModel: viewModel,
            onSave: { [weak self] photos, name in
                self?.onPhotosAdded?(photos, name)
                return nil
            }
        )
        if viewModel.mode == .editor {
            photoPickerFlow?.onPhotosAddedToExisting = { [weak self] in self?.backTapped() }
        }

        // Header container (title, subtitle, guidance, privacy, wide add button)
        let headerStack = UIStackView(arrangedSubviews: [
            titleLabel,
            subtitleLabel,
            guidanceLabel,
            privacyBanner,
            wideAddPhotosButton
        ])
        headerStack.axis = .vertical
        headerStack.spacing = 6
        headerStack.setCustomSpacing(2, after: titleLabel)
        headerStack.setCustomSpacing(2, after: subtitleLabel)
        headerStack.setCustomSpacing(16, after: guidanceLabel)
        headerStack.setCustomSpacing(14, after: privacyBanner)

        [headerStack, collectionView, backButton, moreButton, selectButton, trashButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Top navigation row
            backButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            backButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            moreButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            moreButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),

            selectButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            selectButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),

            trashButton.trailingAnchor.constraint(equalTo: selectButton.leadingAnchor, constant: -10),
            trashButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            trashButton.widthAnchor.constraint(equalToConstant: 44),
            trashButton.heightAnchor.constraint(equalToConstant: 44),

            // Header Stack (below navigation row)
            headerStack.topAnchor.constraint(equalTo: backButton.bottomAnchor, constant: 14),
            headerStack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            headerStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),

            // Wide add photos button height
            wideAddPhotosButton.heightAnchor.constraint(equalToConstant: 50),

            // Grid CollectionView below header stack
            collectionView.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 14),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        renderItems()
        renderSelection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if viewModel.shouldRequestAccessOnAppear() { viewModel.requestAccess { _ in } }
    }

    private func setupMoreMenu() {
        let selectAction = UIAction(title: "Select Photos", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
            self?.viewModel.toggleSelecting()
        }
        let renameAction = UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { [weak self] _ in
            self?.promptRename()
        }
        moreButton.menu = UIMenu(children: [selectAction, renameAction])
        moreButton.showsMenuAsPrimaryAction = true
    }

    private func promptRename() {
        let alert = UIAlertController(title: "Rename Preference", message: "Give this preference a new name.", preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.viewModel.title
            tf.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
            guard let newName = alert?.textFields?.first?.text, let self else { return }
            if let error = self.viewModel.rename(to: newName) {
                self.showAlert(message: error)
            } else {
                self.renderItems()
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Render

    private func renderItems() {
        titleLabel.text = viewModel.displayTitle
        let count = viewModel.items.count
        subtitleLabel.text = "Reference photos · \(count) of \(ChoosePhotosViewModel.maxPhotos)"
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    private func renderSelection() {
        let selecting = viewModel.isSelecting
        selectButton.isHidden = !selecting
        selectButton.updateTitle(viewModel.selectButtonTitle)
        trashButton.isHidden = !selecting
        trashButton.isEnabled = viewModel.canTapDelete
        moreButton.isHidden = selecting
        wideAddPhotosButton.isUserInteractionEnabled = !selecting
        wideAddPhotosButton.alpha = selecting ? 0.4 : 1.0
        titleLabel.text = viewModel.displayTitle
        collectionView.reloadData()
    }

    // MARK: - Navigation

    private func backTapped() {
        switch viewModel.backAction() {
        case .leave:
            onBack?()
        case .confirmDiscard:
            confirmDiscard()
        case .needMorePhotos(let message):
            showAlert(message: message)
        }
    }

    private func confirmDiscard() {
        let alert = UIAlertController(title: "Discard this preference?", message: "The photos you picked won't be saved.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in self?.onBack?() })
        present(alert, animated: true)
    }

    /// Confirmation alert as depicted in Image 1 (iPhone 17 - Preferences C re-analyze):
    /// Title: "Re-analyze the AI preferences"
    /// Message: "By Delete those picture it will redefined the ai model, are you sure ?"
    /// Buttons: [Cancel] (red text) and [Yes]
    private func confirmDelete() {
        let alert = UIAlertController(
            title: "Re-analyze the AI preferences",
            message: "By Delete those picture it will redefined the ai model, are you sure ?",
            preferredStyle: .alert
        )
        let cancelAction = UIAlertAction(title: "Cancel", style: .destructive) { _ in }
        let yesAction = UIAlertAction(title: "Yes", style: .default) { [weak self] _ in
            guard let self else { return }
            self.viewModel.deleteChecked()
            if self.viewModel.mode == .editor { self.backTapped() }
        }
        alert.addAction(cancelAction)
        alert.addAction(yesAction)
        present(alert, animated: true)
    }

    private func showAlert(message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension AIPreferencesViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in cv: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let s = sections
        return s.indices.contains(section) ? s[section].indices.count : 0
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        guard let cell = cv.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseID, for: ip) as? PhotoCell,
              let index = itemIndex(at: ip)
        else { return UICollectionViewCell() }
        cell.imageView.image = viewModel.items[index].image
        cell.selectMode = viewModel.isSelecting
        cell.isChecked = viewModel.isChecked(at: index)
        return cell
    }

    func collectionView(_ cv: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at ip: IndexPath) -> UICollectionReusableView {
        let header = cv.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: SectionHeaderView.reuseID,
                                                         for: ip)
        let s = sections
        if let header = header as? SectionHeaderView, s.indices.contains(ip.section) {
            let sectionInfo = s[ip.section]
            let count = sectionInfo.indices.count
            let photoWord = count == 1 ? "photo" : "photos"
            header.setTitle(sectionInfo.title, countText: "\(count) \(photoWord)")
        }
        return header
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        cv.deselectItem(at: ip, animated: false)
        guard let index = itemIndex(at: ip) else { return }
        if viewModel.isSelecting {
            viewModel.toggleChecked(at: index)
        } else {
            showPhoto(at: index)
        }
    }
}

// MARK: - Wide "+ Add photos" Button (Full width dashed button)

private final class WideAddPhotosButton: UIControl {
    private let dashedLayer = CAShapeLayer()

    private let plusIcon: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "plus"))
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        iv.tintColor = Theme.accent
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let titleLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "Add photos"
        lbl.font = .systemFont(ofSize: 15, weight: .semibold)
        lbl.textColor = Theme.accent
        return lbl
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.accentSubtle
        layer.cornerRadius = 14
        clipsToBounds = true

        dashedLayer.strokeColor = Theme.accentBorder.cgColor
        dashedLayer.fillColor = UIColor.clear.cgColor
        dashedLayer.lineWidth = 1.5
        dashedLayer.lineDashPattern = [6, 4]
        layer.addSublayer(dashedLayer)

        let stack = UIStackView(arrangedSubviews: [plusIcon, titleLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 14)
        dashedLayer.path = path.cgPath
        dashedLayer.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet {
            alpha = isHighlighted ? 0.6 : 1.0
        }
    }
}

// MARK: - Section Header View ("Full body 9 photos")

private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeaderView"

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .bold)
        l.textColor = Theme.text
        return l
    }()

    private let countLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .regular)
        l.textColor = Theme.secondaryText
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
        stack.axis = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String?, countText: String) {
        titleLabel.text = title
        countLabel.text = countText
    }
}
