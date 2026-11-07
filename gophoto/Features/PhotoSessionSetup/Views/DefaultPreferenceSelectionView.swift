//
//  DefaultPreferenceSelectionView.swift
//  gophoto
//
//  Created by Brian Juniarta Darmadi on 06/11/26.
//
import SwiftUI

struct DefaultPreferenceSelectionView: View {
    private enum Card: Hashable, CaseIterable {
        case starter, comingSoon
    }

    @State private var centredCard: Card? = .starter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            header
                .padding(.horizontal, GoPhotoDesign.sessionMargin)
            carousel
        }
        .padding(.top, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoPhotoDesign.sessionBackground)
        .sessionBottomBar {
            SessionPrimaryButton(title: "Continue", isEnabled: centredCard == .starter) { }
        }
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("Pick a starting style")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(GoPhotoDesign.primaryText)
            Text("No photos yet? Start with one of ours. You can add your own photos later.")
                .font(.system(size: 16))
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var carousel: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(Card.allCases, id: \.self) { card in
                    let isCentred = card == centredCard
                    cardView(card)
                        .containerRelativeFrame(.horizontal)
                        .scaleEffect(isCentred || reduceMotion ? 1 : 0.92)
                        .opacity(isCentred || reduceMotion ? 1 : 0.6)
                        .onTapGesture {
                            withAnimation(.snappy) { centredCard = card }
                        }
                        .accessibilityAddTraits(isCentred ? .isSelected : [])
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, GoPhotoDesign.sessionMargin + 24, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centredCard, anchor: .center)
        .sensoryFeedback(.selection, trigger: centredCard)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardView(_ card: Card) -> some View {
        switch card {
        case .starter:
            StarterPresetCard(isSelected: centredCard == .starter)
        case .comingSoon:
            ComingSoonCard()
        }
    }
}

private struct StarterPresetCard: View {
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(GoPhotoDesign.tagBackground)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundStyle(GoPhotoDesign.tagText)
                }
                .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("Starter style")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(GoPhotoDesign.primaryText)
                PresetAspectRow(icon: "square.split.2x1", label: "Composition",
                                text: "You on the left third, the view on the right")
                PresetAspectRow(icon: "figure.stand", label: "Size",
                                text: "Full body, head to feet")
                PresetAspectRow(icon: "camera.rotate", label: "Angle",
                                text: "Phone a little below your eyes")
            }
            .padding(16)
            .fixedSize(horizontal: false, vertical: true)
        }
        .presetCardSurface(isSelected: isSelected)
        .accessibilityElement(children: .combine)
    }
}

private struct ComingSoonCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(GoPhotoDesign.tagText)
            Text("More styles coming soon")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GoPhotoDesign.primaryText)
            Text("We're preparing more ready-made styles.")
                .font(.system(size: 15))
                .foregroundStyle(GoPhotoDesign.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presetCardSurface(isSelected: false)
        .accessibilityElement(children: .combine)
    }
}

private struct PresetAspectRow: View {
    let icon: String
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(GoPhotoDesign.tagText)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(GoPhotoDesign.tagBackground, in: Capsule())
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(GoPhotoDesign.primaryText)
                .lineLimit(2)
        }
    }
}

private extension View {
    func presetCardSurface(isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: GoPhotoDesign.cardCornerRadius, style: .continuous)
        return self
            .background(isSelected ? GoPhotoDesign.selectedCardBackground : GoPhotoDesign.background)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isSelected ? GoPhotoDesign.sessionAccent : GoPhotoDesign.secondaryText.opacity(0.22),
                                   lineWidth: isSelected ? 2 : 1)
            }
    }
}

#Preview {
    NavigationStack {
        DefaultPreferenceSelectionView()
    }
}
