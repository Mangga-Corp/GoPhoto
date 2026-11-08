//
//  SessionSetupComponents.swift
//  gophoto
//
//  Pieces shared by the session setup screens (Preference Selection, and Shot Size Selection in
//  Phase 3): selection indicator, fixed bottom CTA, chips, thumbnails, and a UIKit presenter anchor.
//

import SwiftUI
import UIKit

/// Purple circle with a checkmark when selected, a neutral empty circle otherwise.
struct SelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(GoPhotoDesign.primary)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(GoPhotoDesign.onPrimary)
            } else {
                Circle().fill(GoPhotoDesign.secondaryBackground)
                Circle().strokeBorder(GoPhotoDesign.border, lineWidth: 1)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

/// The fixed bottom primary button ("Continue", "Start Shooting"): `.goPhotoPrimary`.
struct SessionPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.goPhotoPrimary(isLoading: isLoading))
        .disabled(!isEnabled)
    }
}

extension View {
    /// Pins `button` above the bottom safe area on a light bar; the content scrolls behind it.
    func sessionBottomBar<Button: View>(@ViewBuilder _ button: () -> Button) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            button()
                .padding(.horizontal, GoPhotoDesign.sessionMargin)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
                .background {
                    GoPhotoDesign.background
                        .overlay(alignment: .top) {
                            Rectangle().fill(GoPhotoDesign.divider).frame(height: 1)
                        }
                        .ignoresSafeArea(edges: .bottom)
                }
        }
    }
}

/// Small rounded label ("Lighting: Bright").
struct SessionChip: View {
    let text: String
    let onSelectedCard: Bool

    var body: some View {
        Text(text)
            .font(GoPhotoDesign.smallLabel)
            .foregroundStyle(GoPhotoDesign.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(onSelectedCard ? GoPhotoDesign.surface : GoPhotoDesign.secondaryBackground, in: Capsule())
    }
}

/// Lays chips out left to right, wrapping to a new line when they don't fit.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if var last = rows.last, last.width + spacing + size.width <= width {
                last.indices.append(index)
                last.width += spacing + size.width
                last.height = max(last.height, size.height)
                rows[rows.count - 1] = last
            } else {
                rows.append(([index], min(size.width, width), size.height))
            }
        }
        return rows
    }
}

/// A preference photo scaled down off the main thread (the saved photos are full size), or a
/// neutral placeholder when there is none.
struct PreferenceThumbnail: View {
    let image: UIImage?
    let cacheKey: String
    var size = CGSize(width: 84, height: 100)

    @State private var thumbnail: UIImage?
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            GoPhotoDesign.secondaryBackground
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else if image == nil {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(GoPhotoDesign.secondaryText.opacity(0.7))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
        .task(id: cacheKey) { await load() }
    }

    private func load() async {
        guard let image else { thumbnail = nil; return }
        if let cached = Self.cache.object(forKey: cacheKey as NSString) { thumbnail = cached; return }
        let scale = UITraitCollection.current.displayScale
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        // Aspect-fill: scale the shorter side to the target.
        let ratio = max(target.width / image.size.width, target.height / image.size.height)
        let fitted = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let small = await image.byPreparingThumbnail(ofSize: fitted) ?? image
        Self.cache.setObject(small, forKey: cacheKey as NSString)
        thumbnail = small
    }
}

/// Gives SwiftUI screens a UIViewController to present the existing UIKit flows from.
final class PresentationAnchor {
    fileprivate weak var viewController: UIViewController?

    /// The top-most controller currently presented above this screen.
    var presenter: UIViewController? {
        var top = viewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

struct PresentationAnchorView: UIViewControllerRepresentable {
    let anchor: PresentationAnchor

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        anchor.viewController = controller
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        anchor.viewController = controller
    }
}
