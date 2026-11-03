import SwiftUI
import UIKit

struct PhotoSessionPhotoPicker: UIViewControllerRepresentable {
    let onSave: ([PhotoItem], String) -> String?
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> PhotoPreferencePickerEntryViewController {
        PhotoPreferencePickerEntryViewController(onSave: onSave, onFinish: onFinish)
    }

    func updateUIViewController(
        _ uiViewController: PhotoPreferencePickerEntryViewController,
        context: Context
    ) {}
}

final class PhotoPreferencePickerEntryViewController: UIViewController {
    private let onSave: ([PhotoItem], String) -> String?
    private let onFinish: () -> Void
    private var pickerFlow: PhotoPreferencePickerFlow?

    init(onSave: @escaping ([PhotoItem], String) -> String?, onFinish: @escaping () -> Void) {
        self.onSave = onSave
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard pickerFlow == nil else { return }

        let preferences = PreferencesViewModel.shared
        let viewModel = ChoosePhotosViewModel(
            service: ChoosePhotosService(),
            preferenceName: "New Preference",
            items: [],
            mode: .create
        )
        viewModel.validateNewName = { preferences.nameError(for: $0) }

        pickerFlow = PhotoPreferencePickerFlow(
            presenter: self,
            viewModel: viewModel,
            onSave: { [weak self] photos, name in
                guard let self else { return nil }
                let error = self.onSave(photos, name)
                if error == nil {
                    self.onFinish()
                }
                return error
            },
            onCancel: { [weak self] in self?.onFinish() }
        )
        pickerFlow?.start()
    }
}
