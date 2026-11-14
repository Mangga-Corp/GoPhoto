//
//  FacePickerView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 14/11/26.
//

import SwiftUI

struct FacePickerView: View {
    @State private var viewModel = FacePickerViewModel()
    @State private var openedGroup: FaceGroup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Which one is you?")
                    .font(GoPhotoDesign.largeTitle)
                    .foregroundStyle(GoPhotoDesign.primaryText)

                switch viewModel.state {
                case .idle:
                    SessionPrimaryButton(title: "Scan my photos") { viewModel.startScan() }
                case .needsAccess:
                    Text("Allow Poto to access your photos in Settings to scan them.")
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                case .scanning(let checked):
                    ProgressView("Looking for faces… \(checked) photos checked")
                    Button("Cancel") { viewModel.cancelScan() }
                        .buttonStyle(.goPhotoText)
                case .done:
                    faces
                    thresholdControl
                }
            }
            .padding(GoPhotoDesign.sessionMargin)
        }
        .background(GoPhotoDesign.background)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: viewModel.threshold) {
            guard viewModel.state == .done else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await viewModel.regroup()
        }
        .onDisappear { viewModel.clear() }
        .sheet(item: $openedGroup) { group in
            GroupFacesView(group: group)
        }
    }

    private var faces: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                ForEach(viewModel.topGroups) { group in
                    Button { openedGroup = group } label: {
                        VStack(spacing: 6) {
                            if let cover = group.cover {
                                Image(uiImage: UIImage(cgImage: cover.faceCrop))
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(Circle())
                            }
                            Text("\(group.assetIDs.count) photos")
                                .font(GoPhotoDesign.caption)
                                .foregroundStyle(GoPhotoDesign.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("\(viewModel.groups.count) groups from \(viewModel.faceCount) faces")
                .font(GoPhotoDesign.caption)
                .foregroundStyle(GoPhotoDesign.secondaryText)
        }
    }

    private var thresholdControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Same person below \(viewModel.threshold, format: .number.precision(.fractionLength(2)))")
                .font(GoPhotoDesign.caption)
                .foregroundStyle(GoPhotoDesign.secondaryText)
            Slider(value: $viewModel.threshold, in: 0.1...1.5)
        }
    }
}

private struct GroupFacesView: View {
    let group: FaceGroup

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                    ForEach(Array(group.samples.enumerated()), id: \.offset) { _, sample in
                        Image(uiImage: UIImage(cgImage: sample.faceCrop))
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
            .navigationTitle("\(group.assetIDs.count) photos")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
