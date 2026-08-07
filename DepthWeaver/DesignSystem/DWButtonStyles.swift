import SwiftUI

/// Cyan filled button — the single most important action on a screen
/// ("Choose a photo", the trainer's primary step button).
struct DWPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = DWMetric.primaryButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DWFont.ui(14, .semibold))
            .foregroundStyle(DWColor.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(DWColor.cyan, in: RoundedRectangle(cornerRadius: DWRadius.lg, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// White filled button — reserved for "Save" / "Save to Photos", the one action
/// that has to out-rank even the cyan accent.
struct DWWhiteButtonStyle: ButtonStyle {
    var height: CGFloat = DWMetric.primaryButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DWFont.ui(14, .semibold))
            .foregroundStyle(DWColor.ground)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(DWColor.text, in: RoundedRectangle(cornerRadius: DWRadius.xl, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Glass secondary button.
struct DWGlassButtonStyle: ButtonStyle {
    var height: CGFloat = 48

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DWFont.ui(13.5, .medium))
            .foregroundStyle(DWColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .dwGlass(radius: DWRadius.xl)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Square glass button for a trailing icon action (share, next to "Save").
struct DWSquareGlassButtonStyle: ButtonStyle {
    var size: CGFloat = DWMetric.primaryButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(DWColor.text)
            .frame(width: size, height: size)
            .dwGlass(radius: DWRadius.xl)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Round glass button for floating chrome (the "?" and the back arrow).
struct DWCircleGlassButtonStyle: ButtonStyle {
    var size: CGFloat = DWMetric.circleButton

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(DWColor.text)
            .frame(width: size, height: size)
            .dwGlassCircle()
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    VStack(spacing: DWSpace.l) {
        Button("Choose a photo") {}.buttonStyle(DWPrimaryButtonStyle())
        Button("Save to Photos") {}.buttonStyle(DWWhiteButtonStyle())
        Button("Skip the trainer") {}.buttonStyle(DWGlassButtonStyle())
        HStack(spacing: DWSpace.s) {
            Button { } label: { Image(systemName: "square.and.arrow.up") }
                .buttonStyle(DWSquareGlassButtonStyle())
            Button { } label: { Text("?") }
                .buttonStyle(DWCircleGlassButtonStyle())
        }
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DWColor.ground)
}
