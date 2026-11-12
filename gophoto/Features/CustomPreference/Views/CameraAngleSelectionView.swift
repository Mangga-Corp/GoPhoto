//
//  CameraAngleSelectionView.swift
//  gophoto
//
//  Custom preference, step 2: the camera angle. Create Preference saves the placement and angle
//  as a new preference under its combination's name.
//

import SwiftUI

struct CameraAngleSelectionView: View {
    @Bindable var model: CustomPreferenceFlowModel

    var body: some View {
        CustomStyleOptionPage(
            step: 2,
            stepCount: CustomPreferenceFlowModel.stepCount,
            title: "Choose a Camera Angle",
            message: "From where should the photo be taken? The camera will guide your phone's height and tilt.",
            selection: $model.angle,
            isOptionAvailable: { angle in model.isAngleAvailable(angle) },
            primaryTitle: "Create Preference",
            footnote: model.pendingName.map { "Saved to your preferences as “\($0)”" },
            isLoading: model.isSaving,
            onPrimary: model.create
        ) { angle in
            CameraAngleArtwork(angle: angle)
        }
        .navigationBarBackButtonHidden(model.isSaving)
        .alert("Couldn't create the preference", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    let model = CustomPreferenceFlowModel(onCreated: { _ in })
    model.placement = .ruleOfThirds
    return NavigationStack {
        CameraAngleSelectionView(model: model)
    }
}
