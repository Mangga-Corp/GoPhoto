import SwiftUI
import UIKit

enum PhotoSessionPickerEntryMode {
    case createPreference
    case selectPhotos(initialPhotos: [PhotoItem], onSelection: ([PhotoItem]) -> Void)
    case namePreference(photos: [PhotoItem])
}

struct PhotoSessionPhotoPicker: UIViewControllerRepresentable {
    private let mode: PhotoSessionPickerEntryMode
    private let onSave: ([PhotoItem], String) -> String?
    private let onCreatePreference: (([PhotoItem], String, @escaping (String?) -> Void) -> Void)?
    private let onFinish: () -> Void

    init(onSave: @escaping ([PhotoItem], String) -> String?, onFinish: @escaping () -> Void) {
        mode = .createPreference
        self.onSave = onSave
        onCreatePreference = nil
        self.onFinish = onFinish
    }

    init(
        initialPhotos: [PhotoItem],
        onSelection: @escaping ([PhotoItem]) -> Void,
        onFinish: @escaping () -> Void
    ) {
        mode = .selectPhotos(initialPhotos: initialPhotos, onSelection: onSelection)
        onSave = { _, _ in nil }
        onCreatePreference = nil
        self.onFinish = onFinish
    }

    init(
        photosToName: [PhotoItem],
        onCreatePreference: @escaping ([PhotoItem], String, @escaping (String?) -> Void) -> Void,
        onFinish: @escaping () -> Void
    ) {
        mode = .namePreference(photos: photosToName)
        onSave = { _, _ in nil }
        self.onCreatePreference = onCreatePreference
        self.onFinish = onFinish
    }

    func makeUIViewController(context: Context) -> PhotoPreferencePickerEntryViewController {
        PhotoPreferencePickerEntryViewController(
            mode: mode,
            onSave: onSave,
            onCreatePreference: onCreatePreference,
            onFinish: onFinish
        )
    }

    func updateUIViewController(
        _ uiViewController: PhotoPreferencePickerEntryViewController,
        context: Context
    ) {}
}

final class PhotoPreferencePickerEntryViewController: UIViewController {
    private let mode: PhotoSessionPickerEntryMode
    private let onSave: ([PhotoItem], String) -> String?
    private let onCreatePreference: (([PhotoItem], String, @escaping (String?) -> Void) -> Void)?
    private let onFinish: () -> Void
    private var pickerFlow: PhotoPreferencePickerFlow?

    init(
        mode: PhotoSessionPickerEntryMode,
        onSave: @escaping ([PhotoItem], String) -> String?,
        onCreatePreference: (([PhotoItem], String, @escaping (String?) -> Void) -> Void)?,
        onFinish: @escaping () -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        self.onCreatePreference = onCreatePreference
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
        let viewModel: ChoosePhotosViewModel
        switch mode {
        case .createPreference:
            viewModel = makeViewModel(items: [], mode: .create, preferences: preferences)
        case .selectPhotos(let initialPhotos, let onSelection):
            viewModel = makeViewModel(items: initialPhotos, mode: .editor, preferences: preferences)
            viewModel.onPhotosChange = onSelection
        case .namePreference(let photos):
            viewModel = makeViewModel(items: photos, mode: .create, preferences: preferences)
        }

        pickerFlow = PhotoPreferencePickerFlow(
            presenter: self,
            viewModel: viewModel,
            onSave: { [weak self] photos, name in
                guard let self else { return nil }
                let error = self.onSave(photos, name)
                if error == nil { self.onFinish() }
                return error
            },
            onCancel: { [weak self] in self?.onFinish() },
            onPickerFinished: { [weak self] in self?.onFinish() },
            onSaveAsync: onCreatePreference,
            onSaveSuccess: { [weak self] in self?.onFinish() }
        )

        switch mode {
        case .createPreference, .selectPhotos:
            pickerFlow?.start()
        case .namePreference:
            pickerFlow?.startNamingSelection()
        }
    }

    private func makeViewModel(
        items: [PhotoItem],
        mode: ChoosePhotosViewModel.Mode,
        preferences: PreferencesViewModel
    ) -> ChoosePhotosViewModel {
        let viewModel = ChoosePhotosViewModel(
            service: ChoosePhotosService(),
            preferenceName: "New Preference",
            items: items,
            mode: mode
        )
        viewModel.validateNewName = { preferences.nameError(for: $0) }
        return viewModel
    }
}
