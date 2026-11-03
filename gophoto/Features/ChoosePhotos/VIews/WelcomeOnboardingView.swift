import SwiftUI

struct WelcomeOnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let galleryHeight = geometry.size.height * 0.63

            VStack(spacing: 0) {
                WelcomeGalleryView()
                    .frame(height: galleryHeight)

                VStack(spacing: 0) {
                    Spacer(minLength: 18)

                    Text("Start with your best photos")
                        .font(GoPhotoDesign.headline)
                        .foregroundStyle(GoPhotoDesign.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Add your favorite self-portraits as references for your AI guide.")
                        .font(GoPhotoDesign.body)
                        .foregroundStyle(GoPhotoDesign.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 16)

                    Spacer(minLength: 28)

                    Button(action: onContinue) {
                        Text("CHOOSE PHOTOS")
                            .font(GoPhotoDesign.primaryButton)
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: GoPhotoDesign.buttonHeight)
                            .background(GoPhotoDesign.purple)
                            .clipShape(RoundedRectangle(cornerRadius: GoPhotoDesign.buttonCornerRadius, style: .continuous))
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Continue to choose reference photos")
                    .padding(.bottom, 14)
                }
                .padding(.horizontal, GoPhotoDesign.horizontalMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(GoPhotoDesign.background)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(GoPhotoDesign.background)
        }
        .background(GoPhotoDesign.background)
        .ignoresSafeArea(edges: .top)
    }
}
