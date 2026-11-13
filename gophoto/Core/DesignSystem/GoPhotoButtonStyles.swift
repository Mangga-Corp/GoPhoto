import SwiftUI

// The app's three button styles. Every state (normal, pressed, disabled, loading) is defined here.
//
//     Button("Continue") { … }.buttonStyle(.goPhotoPrimary)
//     Button("Back") { … }.buttonStyle(.goPhotoSecondary)
//     Button("Edit") { … }.buttonStyle(.goPhotoText)
//     Button { … } label: { Label("Add Your Photos", systemImage: "plus.circle") }
//         .buttonStyle(.goPhotoPrimary(isLoading: isSaving))
//
// Primary and secondary are full-width capsules of `GoPhotoDesign.buttonHeight`.

/// Tinted Liquid Glass brand button: the one main action of a screen.
struct GoPhotoPrimaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isActive = isEnabled && !isLoading
        let tint: Color = !isEnabled ? GoPhotoDesign.secondaryBackground : GoPhotoDesign.primary
        GoPhotoButtonLabel(configuration: configuration, isLoading: isLoading, spinnerColor: GoPhotoDesign.onPrimary)
            .foregroundStyle(isEnabled ? GoPhotoDesign.onPrimary : GoPhotoDesign.disabledText)
            .frame(maxWidth: .infinity, minHeight: GoPhotoDesign.buttonHeight)
            .glassEffect(.regular.tint(tint).interactive(isActive), in: Capsule())
            .contentShape(Capsule())
            .allowsHitTesting(isActive)
    }
}

/// Lightly tinted Liquid Glass button: a secondary action next to a primary one.
struct GoPhotoSecondaryButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        GoPhotoButtonLabel(configuration: configuration, isLoading: isLoading, spinnerColor: GoPhotoDesign.primary)
            .foregroundStyle(isEnabled ? GoPhotoDesign.primary : GoPhotoDesign.disabledText)
            .frame(maxWidth: .infinity, minHeight: GoPhotoDesign.buttonHeight)
            .glassEffect(.regular.tint(GoPhotoDesign.primary.opacity(isEnabled ? 0.15 : 0)).interactive(isEnabled && !isLoading), in: Capsule())
            .contentShape(Capsule())
            .allowsHitTesting(isEnabled && !isLoading)
    }
}

/// Text-only button (Back, Edit, Add More Photos).
struct GoPhotoTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GoPhotoDesign.buttonLabel)
            .foregroundStyle(isEnabled
                             ? (configuration.isPressed ? GoPhotoDesign.primaryPressed : GoPhotoDesign.primary)
                             : GoPhotoDesign.disabledText)
            .frame(minHeight: GoPhotoDesign.compactButtonHeight)
            .contentShape(Rectangle())
    }
}

/// Label with the shared font, icon spacing and loading spinner (the title stays in layout so the
/// button doesn't change size).
private struct GoPhotoButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let isLoading: Bool
    let spinnerColor: Color

    var body: some View {
        configuration.label
            .font(GoPhotoDesign.buttonLabel)
            .labelStyle(GoPhotoButtonLabelStyle())
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading { ProgressView().tint(spinnerColor) }
            }
            .padding(.horizontal, 20)
    }
}

private struct GoPhotoButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon
        }
    }
}

extension ButtonStyle where Self == GoPhotoPrimaryButtonStyle {
    static var goPhotoPrimary: GoPhotoPrimaryButtonStyle { .init() }
    static func goPhotoPrimary(isLoading: Bool) -> GoPhotoPrimaryButtonStyle { .init(isLoading: isLoading) }
}

extension ButtonStyle where Self == GoPhotoSecondaryButtonStyle {
    static var goPhotoSecondary: GoPhotoSecondaryButtonStyle { .init() }
    static func goPhotoSecondary(isLoading: Bool) -> GoPhotoSecondaryButtonStyle { .init(isLoading: isLoading) }
}

extension ButtonStyle where Self == GoPhotoTextButtonStyle {
    static var goPhotoText: GoPhotoTextButtonStyle { .init() }
}
