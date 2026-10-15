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

/// Compact pill (same look as PillButton, smaller). Visible size is small, tap area stays 44 x 44.
private final class CompactPillButton: UIButton {
    init(title: String) {
        super.init(frame: .zero)
        var c = UIButton.Configuration.plain()
        c.title = title
        c.baseForegroundColor = Theme.text
        c.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var a = $0; a.font = UIFont.preferredFont(forTextStyle: .footnote); return a
        }
        configuration = c
        backgroundColor = Theme.surface
        layer.borderWidth = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool { didSet { alpha = isHighlighted ? 0.6 : 1 } }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.borderColor = Theme.stroke.cgColor
    }

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
            editor.modalPresentationStyle = .fullScreen
            editor.onBack = { [weak editor] in editor?.dismiss(animated: true) }
            presenter.present(editor, animated: true)
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
