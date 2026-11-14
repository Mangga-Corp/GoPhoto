//
//  SubjectPlacementSelectionView.swift
//  gophoto
//
//  Custom preference, step 1: where the subject sits in the frame. Continue opens step 2
//  (Camera Angle) with the same flow model.
//

import SwiftUI

struct SubjectPlacementSelectionView: View {
    @Bindable var model: CustomPreferenceFlowModel
    @State private var isShowingAngles = false

    var body: some View {
        CustomStyleOptionPage(
            step: 1,
            stepCount: CustomPreferenceFlowModel.stepCount,
            title: "Where Should You Stand?",
            message: "Where should you appear in the photo? We'll guide you to that spot.",
            selection: $model.placement,
            isOptionAvailable: { placement in model.isPlacementAvailable(placement) },
            primaryTitle: "Next",
            onPrimary: { isShowingAngles = true }
        ) { placement in
            SubjectPlacementArtwork(placement: placement)
        }
        .navigationDestination(isPresented: $isShowingAngles) {
            CameraAngleSelectionView(model: model)
        }
    }
}

#Preview {
    NavigationStack {
        SubjectPlacementSelectionView(model: CustomPreferenceFlowModel(onCreated: { _ in }))
    }
}
