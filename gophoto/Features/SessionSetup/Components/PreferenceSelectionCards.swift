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
            PreferenceThumbnail(image: card.thumbnail, cacheKey: card.thumbnailKey)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(card.name)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .lineLimit(1)
                        .layoutPriority(0)
                    if card.isLastUsed {
                        Text("Last Used")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(GoPhotoDesign.tagText)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(GoPhotoDesign.tagBackground, in: Capsule())
                            .layoutPriority(1)
                    }
                }

                Text(card.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(GoPhotoDesign.secondaryText)
                    .lineLimit(card.isAvailable ? 1 : 2)

                if card.isUpdating {
                    Label("Updating analysis…", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .medium))
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
        .background(isSelected ? GoPhotoDesign.selectedCardBackground : Color.white,
                    in: RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(isSelected ? 0 : 0.04), radius: 10, x: 0, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous))
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
                    .foregroundStyle(GoPhotoDesign.sessionAccent)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Add New Preference")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.primaryText)
                    // The app analyses the photos with its bundled models; it does not train a model.
                    Text("Add reference portraits to personalize your guidance")
                        .font(.system(size: 14))
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GoPhotoDesign.primaryText.opacity(0.7))
            }
            .padding(16)
            .background(GoPhotoDesign.neutralCardBackground,
                        in: RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the photo picker to create a preference")
    }
}
