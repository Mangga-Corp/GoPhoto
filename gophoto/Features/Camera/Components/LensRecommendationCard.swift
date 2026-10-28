//
//  LensRecommendationCard.swift
//  gophoto
//
//  Beginner-friendly recommendation card for the camera view.
//

import SwiftUI

struct LensRecommendationCard: View {
    let recommendation: LensRecommendation
    let onApply: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(recommendation.reason)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if let caution = recommendation.caution {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text(caution)
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.9))
                }
            }

            Button(action: onApply) {
                Text("Apply")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}
