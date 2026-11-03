//
//  PreferenceEditorPresenter.swift
//  gophoto
//
//  The existing preference photo editor and its analysis → "Your style" card flow, opened from
//  the Preference Selection cards' Edit Photos (moved unchanged out of the camera's former
//  AI Preferences popover).
//

import UIKit

final class PreferenceEditorPresenter {
    private let preferences: PreferencesViewModel
    private let service = ChoosePhotosService()

    init(preferences: PreferencesViewModel = .shared) {
        self.preferences = preferences
    }

    /// Opens the photo editor (add / remove photos, rename by tapping the title) over `presenter`.
    /// When photos changed, closing it shows the analysis and the new style card ("Done").
    /// `onComplete(photosChanged)` runs once everything it presented is dismissed.
    func presentEditor(for id: UUID, from presenter: UIViewController,
                       onComplete: @escaping (_ photosChanged: Bool) -> Void = { _ in }) {
        guard let preference = preferences.preference(id: id) else { return }
        let editorViewModel = ChoosePhotosViewModel(service: service, preferenceName: preference.name, items: preference.photos)
        final class Flag { var value = false }
        let photosChanged = Flag()
        editorViewModel.onPhotosChange = { [weak self] photos in
            photosChanged.value = true
            self?.preferences.updatePhotos(photos, for: id)
        }
        editorViewModel.onRename = { [weak self] name in self?.preferences.rename(id: id, to: name) }
        let editor = AIPreferencesViewController(viewModel: editorViewModel)
        // Group the photos by analysed shot size (four levels); older analyses: full / half body.
        editor.framingOf = { [weak self] photo in
            let analysis = self?.preferences.preference(id: id)?.analysis
            return analysis?.photoShotSizes?[photo.id.uuidString]
                ?? analysis?.photoFramings?[photo.id.uuidString]
        }
        editor.modalPresentationStyle = .fullScreen
        // Photos changed: the analysis runs again, so show it (training) and the new style card.
        editor.onBack = { [weak self, weak editor, weak presenter] in
            guard let self, let editor, photosChanged.value,
                  let photos = self.preferences.preference(id: id)?.photos, !photos.isEmpty else {
                editor?.dismiss(animated: true) { onComplete(photosChanged.value) }
                return
            }
            self.presentAnalysis(of: id, photos: photos, over: editor, buttonTitle: "Done") {
                presenter?.dismiss(animated: true) { onComplete(true) }
            }
        }
        presenter.present(editor, animated: true)
    }

    /// Analysing screen over `host`, then the "Your style" card; `finish` closes the flow.
    func presentAnalysis(of id: UUID, photos: [PhotoItem], over host: UIViewController,
                         buttonTitle: String, finish: @escaping () -> Void) {
        let analyzing = AnalyzingViewController(viewModel: AnalyzingViewModel(preferenceID: id, preferences: preferences),
                                                photos: photos)
        analyzing.modalPresentationStyle = .fullScreen
        analyzing.onFinish = { [weak self, weak analyzing] in
            // No "Your style" card for an unusable result (a required request failed, or no
            // readable person): the flow closes and the card on Preference Selection says why.
            guard let self, let analyzing, let preference = self.preferences.preference(id: id),
                  preference.analysis?.usability == .usable,
                  let summary = StyleSummary(analysis: preference.analysis, photos: preference.photos) else {
                finish()
                return
            }
            let card = StyleCardViewController(summary: summary, buttonTitle: buttonTitle)
            card.modalPresentationStyle = .fullScreen
            card.modalTransitionStyle = .crossDissolve
            card.onDone = finish
            analyzing.present(card, animated: true)
        }
        host.present(analyzing, animated: true)
    }
}
