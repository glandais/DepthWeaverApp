import SwiftUI

// MARK: - Tool chip

/// One segment of the Depth / Pattern / Tune selector. The same view backs both
/// the floating bottom bar and the drawer header, so opening the drawer reads
/// as the bar growing rather than a new control appearing.
struct DWToolChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isSelected: Bool
    var showsIcon: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                if showsIcon {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                }
                Text(title)
                    .font(DWFont.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? DWColor.cyan : DWColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: showsIcon ? 52 : DWMetric.chipHeight)
            .background {
                RoundedRectangle(cornerRadius: DWRadius.xl, style: .continuous)
                    .fill(isSelected ? DWColor.cyanTint : .clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: DWRadius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preset pill

struct DWPresetPill: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    /// The "Custom" pill is a read-out, not a choice — it lights up when the
    /// sliders no longer match any preset.
    var isEnabled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DWFont.ui(11.5, .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(isSelected ? DWColor.ground : DWColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: DWRadius.sm, style: .continuous)
                        .fill(isSelected ? DWColor.text : DWColor.glassFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: DWRadius.sm, style: .continuous)
                                .strokeBorder(isSelected ? .clear : DWColor.hairline, lineWidth: 1)
                        )
                }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Slider row

/// Label + mono hint + cyan mono read-out over a custom track.
///
/// Writes continuously while dragging, exactly like `Slider` did, so the 100 ms
/// debounce in `StereogramViewModel.generateDebounced` stays the only thing
/// throttling regeneration.
struct DWSliderRow: View {
    let title: LocalizedStringKey
    var hint: LocalizedStringKey?
    let valueText: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0
    var accessibilityValueText: String?

    @State private var isDragging = false

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return ((value - range.lowerBound) / span).clamped(to: 0...1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: DWSpace.s) {
                Text(title)
                    .font(DWFont.label)
                    .foregroundStyle(DWColor.text)
                if let hint {
                    Text(hint)
                        .font(DWFont.microMono)
                        .textCase(.uppercase)
                        .foregroundStyle(DWColor.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: DWSpace.s)
                Text(valueText)
                    .font(DWFont.valueMono)
                    .foregroundStyle(DWColor.cyan)
            }
            track
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(accessibilityValueText ?? valueText)
        .accessibilityAdjustableAction { direction in
            let delta = step > 0 ? step : (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(range.upperBound, value + delta)
            case .decrement: value = max(range.lowerBound, value - delta)
            @unknown default: break
            }
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let usable = max(1, proxy.size.width - DWMetric.knob)
            let knobX = DWMetric.knob / 2 + usable * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DWColor.hairlineStrong)
                    .frame(height: DWMetric.track)
                Capsule()
                    .fill(DWColor.cyan)
                    .frame(width: knobX, height: DWMetric.track)
                Circle()
                    .fill(DWColor.text)
                    .frame(width: DWMetric.knob, height: DWMetric.knob)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .scaleEffect(isDragging ? 1.12 : 1)
                    .position(x: knobX, y: proxy.size.height / 2)
            }
            .frame(height: proxy.size.height)
            .contentShape(Rectangle())
            // minimumDistance 0 so a tap on the track jumps the knob; the
            // enclosing ScrollView still wins vertical drags.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let x = (gesture.location.x - DWMetric.knob / 2).clamped(to: 0...usable)
                        update(fraction: x / usable)
                    }
                    .onEnded { _ in isDragging = false }
            )
            .animation(.easeOut(duration: 0.12), value: isDragging)
        }
        .frame(height: 26)
    }

    private func update(fraction: Double) {
        let span = range.upperBound - range.lowerBound
        var newValue = range.lowerBound + span * fraction
        if step > 0 {
            newValue = (newValue / step).rounded() * step
        }
        value = newValue.clamped(to: range)
    }
}

extension DWSliderRow {
    /// Convenience for the `Float` settings (`depthStrength`, `sepFactor`, …).
    init(
        title: LocalizedStringKey,
        hint: LocalizedStringKey? = nil,
        valueText: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float = 0,
        accessibilityValueText: String? = nil
    ) {
        self.init(
            title: title,
            hint: hint,
            valueText: valueText,
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Float($0) }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: Double(step),
            accessibilityValueText: accessibilityValueText
        )
    }

    /// Convenience for the `Int` settings (`dpi`, `oversampling`).
    init(
        title: LocalizedStringKey,
        hint: LocalizedStringKey? = nil,
        valueText: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accessibilityValueText: String? = nil
    ) {
        self.init(
            title: title,
            hint: hint,
            valueText: valueText,
            value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            step: 1,
            accessibilityValueText: accessibilityValueText
        )
    }
}

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

#Preview {
    @Previewable @State var strength: Float = 1.0
    @Previewable @State var preset = 1

    VStack(spacing: DWSpace.xl) {
        HStack(spacing: 6) {
            DWToolChip(title: "Depth", systemImage: "square.3.layers.3d", isSelected: true) {}
            DWToolChip(title: "Pattern", systemImage: "circle.grid.2x2", isSelected: false) {}
            DWToolChip(title: "Tune", systemImage: "slider.horizontal.3", isSelected: false) {}
        }
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                DWPresetPill(title: ["Soft", "Standard", "Punchy", "Custom"][i], isSelected: preset == i) {
                    preset = i
                }
            }
        }
        DWSliderRow(
            title: "Depth",
            hint: "depth strength",
            valueText: String(format: "%.2f", strength),
            value: $strength,
            range: 0.5...2.0,
            step: 0.05
        )
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(DWColor.ground)
}
