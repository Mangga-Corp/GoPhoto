//
//  AIPreferencesButton.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI
import UIKit

/// Use this in CameraView. Small pill, sized to its text.
struct AIPreferencesButton: View {
    var viewModel: PreferencesViewModel = .shared

    var body: some View {
        AIPreferencesButtonRepresentable(viewModel: viewModel).fixedSize()
    }
}

private final class CompactPillButton: UIButton {
    init(title: String) {
        super.init(frame: .zero)
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.title = title
        configuration.cornerStyle = .capsule
        configuration.buttonSize = .small
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFont.preferredFont(forTextStyle: .footnote)
            return attributes
        }
        self.configuration = configuration
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let dx = min(0, (bounds.width - 44) / 2)
        let dy = min(0, (bounds.height - 44) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }
}
private struct AIPreferencesButtonRepresentable: UIViewRepresentable {
    var viewModel: PreferencesViewModel

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeUIView(context: Context) -> CompactPillButton {
        let button = CompactPillButton(title: "AI Preferences")
        let coordinator = context.coordinator
        button.addAction(UIAction { [weak button] _ in
            guard let button else { return }
            coordinator.showPopover(from: button)
        }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: CompactPillButton, context: Context) {}

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        private let viewModel: PreferencesViewModel
        private let service = ChoosePhotosService()

        init(viewModel: PreferencesViewModel) { self.viewModel = viewModel }

        func showPopover(from button: UIView) {
            guard let presenter = button.owningViewController else { return }
            let popover = PreferencesPopoverViewController(viewModel: viewModel)
            popover.modalPresentationStyle = .popover
            popover.onEdit = { [weak self, weak presenter] id in
                presenter?.dismiss(animated: true) { self?.showEditor(for: id, from: presenter) }
            }
            popover.onAdd = { [weak self, weak presenter] in
                presenter?.dismiss(animated: true) { self?.showCreator(from: presenter)}
            }
            if let controller = popover.popoverPresentationController {
                controller.sourceView = button
                controller.sourceRect = button.bounds
                controller.permittedArrowDirections = .up
                controller.delegate = self
            }
            presenter.present(popover, animated: true)
        }

        private func showEditor(for id: UUID, from presenter: UIViewController?) {
            guard let presenter, let preference = viewModel.preference(id: id) else { return }
            let editorViewModel = ChoosePhotosViewModel(service: service, preferenceName: preference.name, items: preference.photos)
            editorViewModel.onPhotosChange = { [weak self] photos in self?.viewModel.updatePhotos(photos, for: id) }
            editorViewModel.onRename = {[weak self] name in self?.viewModel.rename(id: id, to:name)}
            let editor = AIPreferencesViewController(viewModel: editorViewModel)
            // Group the photos by analysed shot size (four levels); older analyses: full / half body.
            editor.framingOf = { [weak self] photo in
                let analysis = self?.viewModel.preference(id: id)?.analysis
                return analysis?.photoShotSizes?[photo.id.uuidString]
                    ?? analysis?.photoFramings?[photo.id.uuidString]
            }
            editor.modalPresentationStyle = .fullScreen
            editor.onBack = { [weak editor] in editor?.dismiss(animated: true) }
            presenter.present(editor, animated: true)
        }

        private func showCreator(from presenter: UIViewController?) {
            guard let presenter else { return }
            let creatorViewModel = ChoosePhotosViewModel(service: service, preferenceName: "New Preference", items: [], mode: .create)
            creatorViewModel.validateNewName = { [weak self] name in self?.viewModel.nameError(for: name)}

            let creator = AIPreferencesViewController(viewModel: creatorViewModel)
            creator.modalPresentationStyle = .fullScreen
            creator.onBack = { [weak creator] in creator?.dismiss(animated: true)}

            creator.onPhotosAdded = { [weak self, weak creator, weak presenter] photos, name in
                guard let self, self.viewModel.add(name: name, photos: photos) == nil else { return }
                let analyzing = AnalyzingViewController(viewModel: AnalyzingViewModel(preferenceID: self.viewModel.selectedID),
                                                        photos: photos)
                analyzing.modalPresentationStyle = .fullScreen
                analyzing.onFinish = { presenter?.dismiss(animated: true)}
                creator?.present(analyzing, animated: true)
            }
            presenter.present(creator, animated: true)

        }

        // Keep it a popover on iPhone (no automatic sheet).
        func adaptivePresentationStyle(for controller: UIPresentationController,
                                       traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
    }
}

private extension UIView {
    var owningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
