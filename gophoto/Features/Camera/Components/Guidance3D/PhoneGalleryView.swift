//
//  PhoneGalleryView.swift
//  gophoto
//
//  Created by Sebastian Darren on 28/10/26.
//

#if DEBUG
import SwiftUI
import UIKit

enum GalleryBackdrop: String, CaseIterable, Identifiable {
    case dark = "Dark", light = "Light", colorful = "Colorful"
    var id: String { rawValue }

    var style: AnyShapeStyle {
        switch self {
        case .dark:     AnyShapeStyle(Color.black)
        case .light:    AnyShapeStyle(Color(white: 0.92))
        case .colorful: AnyShapeStyle(LinearGradient(colors: [.orange, .pink, .purple],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }
    var textColor: Color { self == .light ? .black : .white }
    /// Ghost and chevron colour that stays visible on this backdrop.
    var guideColor: UIColor { self == .light ? UIColor(white: 0.12, alpha: 1) : .white }
}

/// A rounded card with a title, used by every gallery page.
struct GalleryStage<Content: View>: View {
    let title: String
    let backdrop: GalleryBackdrop
    var height: CGFloat = 260
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(height: height)
            .background(backdrop.style, in: RoundedRectangle(cornerRadius: 20))
            .overlay(alignment: .topLeading) {
                Text(title)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(backdrop.textColor.opacity(0.8))
                    .padding(10)
            }
    }
}

struct PhoneGalleryView: View {
    private enum GalleryPage: String, CaseIterable, Identifiable {
        case poses = "Poses", height = "Height"
        var id: String { rawValue }
    }

    @State private var page: GalleryPage = .poses
    @State private var backdrop: GalleryBackdrop = .dark

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Page", selection: $page) {
                    ForEach(GalleryPage.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Background", selection: $backdrop) {
                    ForEach(GalleryBackdrop.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch page {
                case .poses:  PosesGalleryContent(backdrop: backdrop)
                case .height: HeightGalleryContent(backdrop: backdrop)
                }
            }
            .padding()
        }
        .navigationTitle("3D phone gallery")
    }
}

/// Part 2: static poses.
private struct PosesGalleryContent: View {
    let backdrop: GalleryBackdrop
    @State private var customYaw = 20.0
    @State private var customTilt = 15.0

    private let cells: [(title: String, pose: PhonePose)] = [
        ("Front", .front),
        ("Left 45°", .left45),
        ("Tilted up 25°", .tiltedUp25),
        ("Left 45° + tilted up 25°", .left45TiltedUp25),
    ]

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(cells, id: \.title) { cell in
                    GalleryStage(title: cell.title, backdrop: backdrop) { PhoneSceneView(pose: cell.pose) }
                }
            }
            VStack(spacing: 8) {
                GalleryStage(title: "Custom", backdrop: backdrop) {
                    PhoneSceneView(pose: PhonePose(yawDegrees: customYaw, tiltUpDegrees: customTilt))
                }
                slider("Yaw", value: $customYaw, range: -60...60)
                slider("Tilt up", value: $customTilt, range: -40...40)
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).font(AppFont.footnote).frame(width: 60, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue))°").font(AppFont.footnote.monospacedDigit()).frame(width: 44, alignment: .trailing)
        }
    }
}

#Preview("3D phone gallery") {
    NavigationStack { PhoneGalleryView() }
}
#endif
