import UIKit

final class AIPreferencesViewController: UIViewController {
    /// Called when the back button (top-left) is tapped.
    var onBack: (() -> Void)?
    /// Onboarding: called after the picker closes with the newly added photos.
    var onPhotosAdded: (([PhotoItem], String) -> Void)?

    private let viewModel: ChoosePhotosViewModel

    /// Title = preference name. Tap to rename.
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
        titleField.delegate = self
        titleField.text = viewModel.title
        backButton.isHidden = viewModel.isOnboarding
        editButton.isHidden = viewModel.isOnboarding
        titleField.isUserInteractionEnabled = viewModel.canRename
        titleField.rightViewMode = viewModel.canRename ? .unlessEditing : .never

        viewModel.onItemsChange = { [weak self] in self?.renderItems() }
        viewModel.onEditingChange = { [weak self] in self?.renderEditing() }
        backButton.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        editButton.addAction(UIAction { [weak self] _ in self?.viewModel.toggleEditing() }, for: .touchUpInside)
        addButton.addAction(UIAction { [weak self] _ in self?.addTapped() }, for: .touchUpInside)

        // Tap outside the title field to finish renaming (does not block taps on photos).
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        [collectionView, titleField, subtitleLabel, backButton, editButton, emptyLabel, addButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            titleField.topAnchor.constraint(equalTo: safe.topAnchor, constant: 24),
            titleField.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleField.leadingAnchor.constraint(greaterThanOrEqualTo: backButton.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: editButton.leadingAnchor, constant: -8),
            backButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 8),
            backButton.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 44),
            backButton.heightAnchor.constraint(equalToConstant: 44),
            editButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            editButton.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
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
            addButton.heightAnchor.constraint(equalToConstant: 52)
        ])
        renderItems()
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if viewModel.shouldRequestAccessOnAppear() { viewModel.requestAccess { _ in } }
    }

    // MARK: - Render

    private func renderItems() {
        emptyLabel.isHidden = viewModel.hasItems
        collectionView.isHidden = !viewModel.hasItems
        subtitleLabel.isHidden = !viewModel.hasItems
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
            guard let self else { return }
            self.viewModel.append(newItems)
            self.dismiss(animated: true) {
                guard !newItems.isEmpty, self.viewModel.isOnboarding else { return }
                self.askPreferenceName { name in self.onPhotosAdded?(newItems, name) }
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
        alert.addTextField { [weak self, weak confirm] textField in
            textField.placeholder = "Name"
            textField.autocapitalizationType = .words
            textField.addAction(UIAction { action in
                let text = (action.sender as? UITextField)?.text ?? ""
                confirm?.isEnabled = self?.viewModel.isValid(name: text) ?? false
            }, for: .editingChanged)
        }
        alert.addAction(confirm)
        alert.preferredAction = confirm
        present(alert, animated: true)
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
        textField.text = viewModel.title   // shows the accepted name, or restores the old one on error
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
