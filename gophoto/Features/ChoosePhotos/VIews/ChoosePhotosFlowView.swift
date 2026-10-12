//
//  ChoosePhotosFlowView.swift
//  gophoto
//
//  Created by Sebastian Darren on 13/10/26.
//

import SwiftUI

struct ChoosePhotosFlowView: UIViewControllerRepresentable {
    var onCameraTapped: () -> Void = {}

    func makeUIViewController(context: Context) -> AIPreferencesViewController {
        let viewModel = ChoosePhotosViewModel(service: ChoosePhotosService())
        let vc = AIPreferencesViewController(viewModel: viewModel)
        vc.onCameraTapped = onCameraTapped
        return vc
    }
    func updateUIViewController(_ vc: AIPreferencesViewController, context: Context) {}
}
