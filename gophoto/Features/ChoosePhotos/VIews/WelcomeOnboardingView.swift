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
                        .font(GoPhotoDesign.pageTitle)
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

                    Button("Choose Photos", action: onContinue)
                        .buttonStyle(.goPhotoPrimary)
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
