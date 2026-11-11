//
//  CustomPreferenceFlowModel.swift
//  gophoto
//
//  State of the custom preference flow: Subject Placement → Camera Angle → saved. The two
//  choices are temporary until Create Preference saves them; the screen that opened the flow
//  decides where to go next through `onCreated`.
//

import Foundation
import Observation

@Observable
final class CustomPreferenceFlowModel {
    var placement: SubjectPlacement?
    var angle: CameraAngleStyle?
    private(set) var isSaving = false
    var errorMessage: String?

    @ObservationIgnored private let preferences: PreferencesViewModel
    @ObservationIgnored private let onCreated: (UUID) -> Void

    init(preferences: PreferencesViewModel = .shared, onCreated: @escaping (UUID) -> Void) {
        self.preferences = preferences
        self.onCreated = onCreated
    }

    static let stepCount = 2

    /// Both choices made.
    var style: CustomPreferenceStyle? {
        guard let placement, let angle else { return nil }
        return CustomPreferenceStyle(placement: placement, angle: angle)
    }

    /// The name the preference will be saved with (numbered when already used).
    var pendingName: String? {
        style.map { CustomPreferenceNaming.uniqueName($0.suggestedName, existing: preferences.preferences.map(\.name)) }
    }

    /// Saves the preference, then hands its ID to the opener. Errors stay on this screen.
    func create() {
        guard let style, !isSaving else { return }
        isSaving = true
        preferences.addCustomPersisted(style: style) { [weak self] result in
            guard let self else { return }
            isSaving = false
            switch result {
            case .success(let id):
                onCreated(id)
            case .failure(let error):
                errorMessage = error.message
            }
        }
    }
}
