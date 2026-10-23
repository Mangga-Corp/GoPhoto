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

    /// Title = preference name. Tap to rename (shows the selection count while selecting).
    private let titleField: UITextField = {
        let field = UITextField()
        field.font = .preferredFont(forTextStyle: .title3)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = Theme.text
        field.textAlignment = .center
        field.returnKeyType = .done
        field.autocapitalizationType = .words
        field.clearButtonMode = .whileEditing
        field.accessibilityLabel = "Preference name"
        field.accessibilityHint = "Double tap to rename"
        let icon = UIImageView(image: UIImage(systemName: "pencil"))
        icon.tintColor = Theme.text.withAlphaComponent(0.5)
        icon.contentMode = .center
        icon.frame = CGRect(x: 0, y: 0, width: 28, height: 20)
        field.rightView = icon
        field.rightViewMode = .unlessEditing
        return field
    }()
    private let subtitleLabel = UILabel.make("", style: .footnote)
    private let emptyLabel = UILabel.make("You haven’t input any photo", style: .subheadline)
    private let selectButton = PillButton(title: "Select")
    private let addButton = CircleButton(symbol: "plus", accessibilityLabel: "Add photos")
    private let trashButton = CircleButton(symbol: "trash", accessibilityLabel: "Delete", tint: .systemRed)
    private let backButton = CircleButton(symbol: "chevron.left", accessibilityLabel: "Back")
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { [weak self] index, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.25), heightDimension: .fractionalHeight(1)))
            item.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.25)), subitems: [item])
            let section = NSCollectionLayoutSection(group: group)
            let sections = self?.sections ?? []
            let isLast = index >= sections.count - 1
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: isLast ? 120 : 16, trailing: 10)
            if sections.indices.contains(index), sections[index].title != nil {
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .estimated(32)),
                    elementKind: UICollectionView.elementKindSectionHeader, alignment: .top)
                section.boundarySupplementaryItems = [header]
            }
            return section
        }
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    /// The grid's sections: Full body, Half body, then the rest. One untitled section when the
    /// photos are not analysed yet (or `framingOf` is nil).
    private var sections: [(title: String?, indices: [Int])] {
        let all = Array(viewModel.items.indices)
        guard let framingOf else { return [(nil, all)] }
        let framings = all.map { framingOf(viewModel.items[$0]) }
        let full = all.filter { framings[$0] == "fullBody" }
        let half = all.filter { framings[$0] == "halfBody" }
        let rest = all.filter { framings[$0] != "fullBody" && framings[$0] != "halfBody" }
        if full.isEmpty && half.isEmpty { return [(nil, all)] }
        let groups: [(title: String?, indices: [Int])] = [("Full body", full), ("Half body", half), ("Other", rest)]
        return groups.filter { !$0.indices.isEmpty }
    }

    /// Where photo `item` (index into `viewModel.items`) sits in the grid.
    private func indexPath(forItem item: Int) -> IndexPath? {
        for (section, group) in sections.enumerated() {
            if let row = group.indices.firstIndex(of: item) { return IndexPath(item: row, section: section) }
        }
        return nil
    }

    private static func framingTitle(_ framing: String) -> String? {
        switch framing {
        case "fullBody": "Full body"
        case "halfBody": "Half body"
        default: nil
        }
    }

    /// Opens the full-screen viewer on photo `item`, zooming out of its grid cell (swipe down to close).
    private func showPhoto(at item: Int) {
        let order = sections.flatMap { $0.indices }       // pages follow the grid order
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
                // Keep the cell on screen so closing zooms back into the right photo.
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

    /// The photo index (into `viewModel.items`) shown at `indexPath`.
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
        view.backgroundColor = Theme.background
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseID)
        collectionView.register(SectionHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: SectionHeaderView.reuseID)
        titleField.delegate = self
        selectButton.isHidden = !viewModel.showsSelectButton

        viewModel.onItemsChange = { [weak self] in self?.renderItems() }
        viewModel.onSelectionChange = { [weak self] in self?.renderSelection() }
        backButton.addAction(UIAction { [weak self] _ in self?.backTapped() }, for: .touchUpInside)
        selectButton.addAction(UIAction { [weak self] _ in self?.viewModel.toggleSelecting() }, for: .touchUpInside)
        addButton.addAction(UIAction { [weak self] _ in self?.addTapped() }, for: .touchUpInside)
        trashButton.addAction(UIAction { [weak self] _ in self?.confirmDelete() }, for: .touchUpInside)

        // Tap outside the title field to finish renaming (does not block taps on photos).
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        [collectionView, titleField, subtitleLabel, backButton, selectButton, emptyLabel, addButton, trashButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: safe.topAnchor, constant: 24),
            titleField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleField.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: selectButton.leadingAnchor, constant: -8),
            backButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            selectButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            selectButton.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),
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
            addButton.heightAnchor.constraint(equalToConstant: 52),
            trashButton.trailingAnchor.constraint(equalTo: addButton.trailingAnchor),
            trashButton.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),
            trashButton.widthAnchor.constraint(equalToConstant: 52),
            trashButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        renderItems()
        renderSelection()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if viewModel.shouldRequestAccessOnAppear() { viewModel.requestAccess { _ in } }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    // MARK: - Render

    private func renderItems() {
        emptyLabel.isHidden = viewModel.hasItems
        collectionView.isHidden = !viewModel.hasItems
        subtitleLabel.isHidden = !viewModel.hasItems
        subtitleLabel.text = viewModel.subtitleText
        collectionView.reloadData()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Select mode like Photos: title shows the count, Back and + are replaced by Cancel and the trash.
    private func renderSelection() {
        let selecting = viewModel.isSelecting
        let canRename = viewModel.canRename && !selecting
        selectButton.updateTitle(viewModel.selectButtonTitle)
        titleField.text = viewModel.displayTitle
        titleField.isUserInteractionEnabled = canRename
        titleField.rightViewMode = canRename ? .unlessEditing : .never
        backButton.isHidden = !viewModel.showsBackButton || selecting
        addButton.isHidden = selecting
        trashButton.isHidden = !selecting
        trashButton.isEnabled = viewModel.canTapDelete
        collectionView.reloadData()
    }

    // MARK: - Navigation

//    private func backTapped() {
//        if let message = viewModel.minimumPhotosMessage {
//            showAlert(message: message)
//            return
//        }
//        onBack?()
//    }
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
            guard let self else { return }
            self.viewModel.append(newItems)
            self.dismiss(animated: true) {
                guard !newItems.isEmpty, self.viewModel.asksNameAfterPicking else { return }
                if let message = self.viewModel.minimumPhotosMessage {
                    self.showAlert(message: message)
                    return
                }
                self.askPreferenceName { name in self.onPhotosAdded?(self.viewModel.items, name) }
            }
        }
        present(vc, animated: true)
    }

    private func askPreferenceName(completion: @escaping (String) -> Void) {
        let alert = UIAlertController(title: viewModel.namePromptTitle,
                                      message: viewModel.namePromptMessage, preferredStyle: .alert)
        let confirm = UIAlertAction(title: "Continue", style: .default) { [weak alert] _ in
            let name = alert?.textFields?.first?.text ?? ""
            completion(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        confirm.isEnabled = false
        alert.addTextField { [weak self, weak confirm, weak alert] textField in
            textField.placeholder = "Name"
            textField.autocapitalizationType = .words
            textField.addAction(UIAction { [weak alert] action in
                guard let self else { return }
                let text = (action.sender as? UITextField)?.text ?? ""
                let error = self.viewModel.nameError(for: text)
                confirm?.isEnabled = error == nil
                alert?.message = (error == nil || text.isEmpty) ? self.viewModel.namePromptMessage : error
            }, for: .editingChanged)
        }
        alert.addAction(confirm)
        alert.preferredAction = confirm
        present(alert, animated: true)
    }

    /// Confirmation like the Photos app: an action sheet with a destructive button and Cancel.
    private func confirmDelete() {
        let sheet = UIAlertController(title: nil, message: viewModel.deleteConfirmMessage, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: viewModel.deleteConfirmTitle, style: .destructive) { [weak self] _ in
            self?.viewModel.deleteChecked()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = trashButton
        sheet.popoverPresentationController?.sourceRect = trashButton.bounds
        present(sheet, animated: true)
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

extension AIPreferencesViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        if let error = viewModel.rename(to: textField.text ?? "") { showAlert(message: error) }
        textField.text = viewModel.displayTitle   // shows the accepted name, or restores the old one on error
    }
}

extension AIPreferencesViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func numberOfSections(in cv: UICollectionView) -> Int { sections.count }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let sections = self.sections
        return sections.indices.contains(section) ? sections[section].indices.count : 0
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
        let sections = self.sections
        if let header = header as? SectionHeaderView, sections.indices.contains(ip.section) {
            let section = sections[ip.section]
            header.label.text = section.title.map { "\($0) · \(section.indices.count)" }
        }
        return header
    }

    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        cv.deselectItem(at: ip, animated: false)   // we track "checked" ourselves
        guard let index = itemIndex(at: ip) else { return }
        if viewModel.isSelecting {
            viewModel.toggleChecked(at: index)
        } else {
            showPhoto(at: index)
        }
    }
}

/// Title above a group of photos (Full body / Half body).
private final class SectionHeaderView: UICollectionReusableView {
    static let reuseID = "SectionHeaderView"
    let label = UILabel.make("", style: .headline)

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .natural
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
