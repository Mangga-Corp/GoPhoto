import UIKit

final class PhotoPreferencePickerFlow {
    private weak var presenter: UIViewController?
    private let viewModel: ChoosePhotosViewModel
    private let onSave: ([PhotoItem], String) -> String?
    private let onCancel: () -> Void
    private let onPickerFinished: (() -> Void)?
    private let onSaveAsync: (([PhotoItem], String, @escaping (String?) -> Void) -> Void)?
    private let onSaveSuccess: (() -> Void)?
    private var isSavingPreference = false

    init(
        presenter: UIViewController,
        viewModel: ChoosePhotosViewModel,
        onSave: @escaping ([PhotoItem], String) -> String?,
        onCancel: @escaping () -> Void = {},
        onPickerFinished: (() -> Void)? = nil,
        onSaveAsync: (([PhotoItem], String, @escaping (String?) -> Void) -> Void)? = nil,
        onSaveSuccess: (() -> Void)? = nil
    ) {
        self.presenter = presenter
        self.viewModel = viewModel
        self.onSave = onSave
        self.onCancel = onCancel
        self.onPickerFinished = onPickerFinished
        self.onSaveAsync = onSaveAsync
        self.onSaveSuccess = onSaveSuccess
    }

    func start() {
        switch viewModel.addTapped() {
        case .limitReached:
            showAlert(message: viewModel.limitMessage)
        case .permission:
            viewModel.requestAccess { [weak self] canBrowse in
                if canBrowse {
                    self?.presentPicker()
                } else {
                    self?.showSettingsAlert()
                }
            }
        case .picker:
            presentPicker()
        case .settings:
            showSettingsAlert()
        }
    }

    private func presentPicker() {
        let picker = SelectPhotoViewController(viewModel: viewModel.makePickerViewModel())
        picker.modalPresentationStyle = .fullScreen
        picker.onCancel = { [weak self, weak picker] in
            picker?.dismiss(animated: true) {
                self?.onCancel()
            }
        }
        picker.onDone = { [weak self, weak picker] newItems in
            guard let self else { return }
            self.viewModel.append(newItems)
            picker?.dismiss(animated: true) {
                guard !newItems.isEmpty else {
                    self.onPickerFinished?()
                    return
                }
                if self.viewModel.asksNameAfterPicking {
                    self.continueAfterSelection()
                } else {
                    self.onPickerFinished?()
                }
            }
        }
        presenter?.present(picker, animated: true)
    }

    func startNamingSelection() {
        continueAfterSelection()
    }

    private func continueAfterSelection() {
        guard let message = viewModel.minimumPhotosMessage else {
            askPreferenceName()
            return
        }

        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Add Photos", style: .default) { [weak self] _ in
            self?.start()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.onCancel()
        })
        alert.view.tintColor = Theme.accent
        presenter?.present(alert, animated: true)
    }

    private func askPreferenceName() {
        guard let presenter, !isSavingPreference else { return }
        PreferenceNamePrompt.present(from: presenter, viewModel: viewModel, onCancel: onCancel) { [weak self] name in
            guard let self else { return }
            if let onSaveAsync = self.onSaveAsync {
                let flow = self
                flow.isSavingPreference = true
                let progress = UIAlertController(
                    title: "Saving Preference",
                    message: "Saving your selected photos…",
                    preferredStyle: .alert
                )
                flow.presenter?.present(progress, animated: true)
                onSaveAsync(flow.viewModel.items, name) { [weak preferenceFlow = flow] error in
                    DispatchQueue.main.async {
                        guard let preferenceFlow else { return }
                        preferenceFlow.isSavingPreference = false
                        progress.dismiss(animated: true) {
                            if let error {
                                preferenceFlow.showAlert(message: error) {
                                    preferenceFlow.askPreferenceName()
                                }
                            } else {
                                preferenceFlow.onSaveSuccess?()
                            }
                        }
                    }
                }
                return
            }
            if let error = self.onSave(self.viewModel.items, name) {
                self.showAlert(message: error) { [weak self] in self?.askPreferenceName() }
            }
        }
    }

    private func showAlert(message: String, onDismiss: @escaping () -> Void = {}) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in onDismiss() })
        alert.view.tintColor = Theme.accent
        presenter?.present(alert, animated: true)
    }

    private func showSettingsAlert() {
        let alert = UIAlertController(
            title: "Photo Access Needed",
            message: "Allow photo access in Settings to choose photos.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.onCancel()
        })
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { [weak self] _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            self?.onCancel()
        })
        alert.view.tintColor = Theme.accent
        presenter?.present(alert, animated: true)
    }
}

enum PreferenceNamePrompt {
    static func present(
        from presenter: UIViewController,
        viewModel: ChoosePhotosViewModel,
        onCancel: @escaping () -> Void = {},
        completion: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(
            title: viewModel.namePromptTitle,
            message: viewModel.namePromptMessage,
            preferredStyle: .alert
        )
        let confirm = UIAlertAction(title: "Continue", style: .default) { [weak alert] _ in
            let name = alert?.textFields?.first?.text ?? ""
            completion(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        confirm.isEnabled = false
        alert.addTextField { [weak confirm, weak alert] textField in
            textField.placeholder = "Name"
            textField.autocapitalizationType = .words
            textField.addAction(UIAction { [weak alert] action in
                let text = (action.sender as? UITextField)?.text ?? ""
                let error = viewModel.nameError(for: text)
                confirm?.isEnabled = error == nil
                alert?.message = (error == nil || text.isEmpty)
                    ? viewModel.namePromptMessage
                    : error
            }, for: .editingChanged)
        }
        alert.addAction(confirm)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in onCancel() })
        alert.preferredAction = confirm
        alert.view.tintColor = Theme.accent
        presenter.present(alert, animated: true)
    }
}
