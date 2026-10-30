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
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color(red: 17 / 255, green: 17 / 255, blue: 17 / 255))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Add your favorite self-portraits as references for your AI guide.")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color(red: 133 / 255, green: 133 / 255, blue: 133 / 255))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.top, 16)

                    Spacer(minLength: 28)

                    Button(action: onContinue) {
                        Text("CONTINUE")
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 62)
                            .background(Color(red: 146 / 255, green: 131 / 255, blue: 189 / 255))
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 7)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Continue to choose reference photos")
                    .padding(.bottom, 14)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(.white)
        }
        .background(.white)
        .ignoresSafeArea(edges: .top)
    }
}
