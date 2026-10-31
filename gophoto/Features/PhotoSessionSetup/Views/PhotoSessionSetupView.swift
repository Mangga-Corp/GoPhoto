import SwiftUI

struct PhotoSessionSetupView: View {
    let onPreferenceSaved: (UUID) -> Void
    @State private var isPresentingPhotoPicker = false

    init(onPreferenceSaved: @escaping (UUID) -> Void = { _ in }) {
        self.onPreferenceSaved = onPreferenceSaved
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                PhotoSessionEmptyStateView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 0) {
                    Button {
                        isPresentingPhotoPicker = true
                    } label: {
                        Label("ADD YOUR PHOTOS", systemImage: "photo.badge.plus")
                            .font(GoPhotoDesign.primaryButton)
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: GoPhotoDesign.buttonHeight)
                            .background(
                                GoPhotoDesign.purple,
                                in: RoundedRectangle(
                                    cornerRadius: GoPhotoDesign.buttonCornerRadius,
                                    style: .continuous
                                )
                            )
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 7)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, GoPhotoDesign.horizontalMargin)

                    NavigationLink {
                        ExplorePreferencesPlaceholderView()
                    } label: {
                        Text("Explore preferences instead")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GoPhotoDesign.purple)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)

                    PrivacyFooterView()
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
            }
            .background(GoPhotoDesign.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $isPresentingPhotoPicker) {
                PhotoSessionPhotoPicker(
                    onSave: { photos, name in
                        let preferences = PreferencesViewModel.shared
                        let error = preferences.add(name: name, photos: photos)
                        if error == nil, let preferenceID = preferences.selectedID {
                            onPreferenceSaved(preferenceID)
                        }
                        return error
                    },
                    onFinish: { isPresentingPhotoPicker = false }
                )
                .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        Text("Photo Session Setup")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(GoPhotoDesign.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: 76)
        .background(GoPhotoDesign.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GoPhotoDesign.primaryText.opacity(0.06))
                .frame(height: 1)
        }
    }
}

private struct PhotoSessionEmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("No photos yet")
                .font(GoPhotoDesign.headline)
                .foregroundStyle(GoPhotoDesign.primaryText)
                .multilineTextAlignment(.center)

            Text("Add your favorite portraits to get started.")
                .font(GoPhotoDesign.body)
                .foregroundStyle(GoPhotoDesign.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 320)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
    }
}

private struct PrivacyFooterView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 13, weight: .medium))
            Text("Your photos stay private on your iPhone.")
                .font(.system(size: 14, weight: .regular))
        }
        .foregroundStyle(GoPhotoDesign.secondaryText)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }
}

struct ExplorePreferencesPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GoPhotoDesign.purple)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to Photo Session Setup")
                Spacer()
            }
            .padding(.horizontal, 18)
            .frame(height: 64)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoPhotoDesign.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
