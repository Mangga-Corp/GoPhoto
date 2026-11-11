//
//  PreferenceSelectionCards.swift
//  gophoto
//
//  Cards of the Preference Selection screen: one per saved preference, and Add New Preference.
//

import SwiftUI

struct PreferenceSelectionCard: View {
    let card: PreferenceCardModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            if let style = card.customStyle {
                CustomPreferenceThumbnail(style: style)
            } else {
                PreferenceThumbnail(image: card.thumbnail, cacheKey: card.thumbnailKey)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(card.name)
                        .font(GoPhotoDesign.cardTitle)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .lineLimit(1)
                        .layoutPriority(0)
                    if card.isLastUsed {
                        Text("Last Used")
                            .lineLimit(1)
                            .fixedSize()
                            .goPhotoTag()
                            .layoutPriority(1)
                    }
                }

                Text(card.summary)
                    .font(GoPhotoDesign.secondaryBody)
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                    .lineLimit(card.isAvailable ? 1 : 2)

                if card.isUpdating {
                    Label("Updating analysis…", systemImage: "arrow.triangle.2.circlepath")
                        .font(GoPhotoDesign.smallLabel)
                        .foregroundStyle(GoPhotoDesign.tagText)
                } else if !card.chips.isEmpty {
                    ChipFlowLayout {
                        ForEach(card.chips, id: \.self) { SessionChip(text: $0, onSelectedCard: isSelected) }
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingIndicator
        }
        .padding(14)
        .goPhotoCard(isSelected: isSelected)
    }

    @ViewBuilder private var trailingIndicator: some View {
        switch card.availability {
        case .available:
            SelectionIndicator(isSelected: isSelected)
        case .analyzing:
            ProgressView()
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        case .unavailable:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 22))
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
        }
    }
}

struct AddPreferenceCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(GoPhotoDesign.primary)
                    .frame(width: 44, height: 44)
                    .background(GoPhotoDesign.surface, in: RoundedRectangle(cornerRadius: GoPhotoDesign.controlCornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add New Preference")
                        .font(GoPhotoDesign.cardTitle)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                    // The app analyses the photos with its bundled models; it does not train a model.
                    Text("Add reference portraits to personalize your guidance")
                        .font(GoPhotoDesign.secondaryBody)
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoPhotoDesign.secondaryText)
            }
            .padding(16)
            .goPhotoCard(fill: GoPhotoDesign.secondaryBackground)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the photo picker to create a preference")
    }
}
