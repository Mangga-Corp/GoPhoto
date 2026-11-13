//
//  PhotoSourceChoiceView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 13/11/26.
//
import SwiftUI

enum PhotoPickMethod: CaseIterable, Identifiable {
    case suggested, manual

    var id: Self { self }

    var title: String {
        switch self {
        case .suggested: "Find my photos for me"
        case .manual: "Choose photos myself"
        }
    }

    var subtitle: String {
        switch self {
        case .suggested: "Poto looks through your library and picks photos of you"
        case .manual: "Pick photos from your library yourself"
        }
    }

    var symbol: String {
        switch self {
        case .suggested: "sparkles"
        case .manual: "hand.tap"
        }
    }
}

struct PhotoSourceChoiceView: View {
    let onChoose: (PhotoPickMethod) -> Void

    @State private var selected = PhotoPickMethod.suggested

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How do you want to add photos?")
                .font(GoPhotoDesign.largeTitle)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("You can still add or remove photos before the analysis starts.")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 12) {
                ForEach(PhotoPickMethod.allCases) { source in
                    PhotoSourceCard(source: source, isSelected: source == selected)
                        .onTapGesture { selected = source }
                }
            }
            .padding(.top, 28)
        }
        .padding(.horizontal, GoPhotoDesign.sessionMargin)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GoPhotoDesign.background)
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue") { onChoose(selected) }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PhotoSourceCard: View {
    let source: PhotoPickMethod
    let isSelected: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous)
        HStack(spacing: 16) {
            Image(systemName: source.symbol)
                .font(.title2)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(source.title)
                        .font(GoPhotoDesign.cardTitle)
                    if source == .suggested {
                        Text("Recommended")
                            .font(GoPhotoDesign.smallLabel)
                            .foregroundStyle(GoPhotoDesign.tagText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GoPhotoDesign.tagBackground, in: Capsule())
                    }
                }
                Text(source.subtitle)
                    .font(GoPhotoDesign.secondaryBody)
                    .foregroundStyle(isSelected ? GoPhotoDesign.primary : GoPhotoDesign.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle" : "circle")
                .font(.title2)
        }
        .foregroundStyle(isSelected ? GoPhotoDesign.primary : GoPhotoDesign.primaryText)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? GoPhotoDesign.primarySubtle : GoPhotoDesign.surface, in: shape)
        .overlay {
            shape.strokeBorder(isSelected ? GoPhotoDesign.primaryBorder : GoPhotoDesign.border,
                               lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    NavigationStack {
        PhotoSourceChoiceView { _ in }
    }
}
