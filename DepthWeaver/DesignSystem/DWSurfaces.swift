import SwiftUI

/// The floating-chrome treatment used everywhere in the redesign: a blurred
/// material, a faint white fill on top of it, and a hairline border.
struct DWGlassBackground<S: InsettableShape>: ViewModifier {
    let shape: S
    let raised: Bool

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(raised ? DWColor.glassFillRaised : DWColor.glassFill))
                    .overlay(
                        shape.strokeBorder(
                            raised ? DWColor.hairlineStrong : DWColor.hairline,
                            lineWidth: 1
                        )
                    )
            }
    }
}

extension View {
    func dwGlass(radius: CGFloat = DWRadius.xl, raised: Bool = false) -> some View {
        modifier(
            DWGlassBackground(
                shape: RoundedRectangle(cornerRadius: radius, style: .continuous),
                raised: raised
            )
        )
    }

    func dwGlassCapsule(raised: Bool = false) -> some View {
        modifier(DWGlassBackground(shape: Capsule(), raised: raised))
    }

    func dwGlassCircle(raised: Bool = false) -> some View {
        modifier(DWGlassBackground(shape: Circle(), raised: raised))
    }

    /// A non-interactive gradient that keeps floating controls legible over the
    /// stereogram canvas.
    func dwScrim(edge: VerticalEdge, height: CGFloat) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            LinearGradient(
                colors: edge == .top
                    ? [DWColor.scrim, DWColor.scrimClear]
                    : [DWColor.scrimClear, DWColor.scrim],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            .allowsHitTesting(false)
        }
    }
}

/// Hairline separator for grouped lists, inset to clear the leading icon tile.
struct DWSeparator: View {
    var leadingInset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(DWColor.hairline)
            .frame(height: 1)
            .padding(.leading, leadingInset)
    }
}
