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
                    MarqueeText(
                        text: card.name,
                        font: GoPhotoDesign.cardTitle,
                        color: GoPhotoDesign.primaryText
                    )
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

/// Displays text as static if it fits within the available width; if it overflows, it scrolls continuously in an infinite circular marquee loop.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var startDate = Date()

    private var textWidth: CGFloat {
        let uiFont = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .headline).pointSize, weight: .semibold)
        let size = (text as NSString).size(withAttributes: [.font: uiFont])
        return ceil(size.width)
    }

    private let gap: CGFloat = 44
    private let speed: CGFloat = 30 // pt / second
    private let initialPause: Double = 1.2 // pause at start before scrolling

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let overflow = textWidth > containerWidth && containerWidth > 0

            if overflow {
                let pitch = textWidth + gap
                let scrollDuration = Double(pitch / speed)

                TimelineView(.animation) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(startDate))
                    let progress: CGFloat = {
                        if elapsed < initialPause {
                            return 0
                        }
                        let scrollElapsed = elapsed - initialPause
                        let remainder = scrollElapsed.truncatingRemainder(dividingBy: scrollDuration)
                        return CGFloat(remainder / scrollDuration)
                    }()
                    let currentOffset = -progress * pitch

                    HStack(spacing: gap) {
                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Text(text)
                            .font(font)
                            .foregroundStyle(color)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: currentOffset)
                    .frame(width: containerWidth, alignment: .leading)
                }
                .clipped()
                .id(text)
                .onAppear {
                    startDate = Date()
                }
            } else {
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: containerWidth, alignment: .leading)
            }
        }
        .frame(height: 22)
    }
}
