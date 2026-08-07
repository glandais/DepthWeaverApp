#if os(iOS)
import SwiftUI

/// Drawer tab for the generator settings.
///
/// The three sliders that actually change how the illusion feels are named in
/// plain words with the technical term as a hint underneath; DPI and the depth
/// ranges — the ones you only touch if you know why — live behind Advanced.
struct TuneToolView: View {
    @Binding var settings: StereogramSettings
    @Binding var depthMap: DepthMap?
    @Binding var path: NavigationPath

    @State private var showAdvanced = false

    private var activePreset: StereogramPreset? { StereogramPreset.matching(settings) }

    var body: some View {
        VStack(alignment: .leading, spacing: DWSpace.l) {
            presets
            sliders
            advanced
        }
    }

    // MARK: - Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: DWSpace.s) {
            DWSectionLabel("tune.preset_label")
            HStack(spacing: 6) {
                ForEach(StereogramPreset.allCases) { preset in
                    DWPresetPill(title: title(for: preset), isSelected: activePreset == preset) {
                        preset.apply(to: &settings)
                    }
                }
                // Not a choice — it lights up when the sliders match no preset.
                DWPresetPill(title: "tune.preset.custom", isSelected: activePreset == nil, isEnabled: false)
            }
        }
    }

    private func title(for preset: StereogramPreset) -> LocalizedStringKey {
        switch preset {
        case .soft: "tune.preset.soft"
        case .standard: "tune.preset.standard"
        case .punchy: "tune.preset.punchy"
        }
    }

    // MARK: - Sliders

    private var sliders: some View {
        VStack(alignment: .leading, spacing: DWSpace.l) {
            DWSliderRow(
                title: "tune.depth",
                hint: "tune.depth_hint",
                valueText: String(format: "%.2f", settings.depthStrength),
                value: $settings.depthStrength,
                range: 0.5...2.0,
                step: 0.05,
                accessibilityValueText: String(format: "%.2f", settings.depthStrength)
            )

            DWSliderRow(
                title: "tune.spread",
                hint: "tune.spread_hint",
                valueText: String(format: "%.2f", settings.sepFactor),
                value: $settings.sepFactor,
                range: 0.40...0.70,
                step: 0.01,
                accessibilityValueText: String(format: "%.2f", settings.sepFactor)
            )

            DWSliderRow(
                title: "tune.smoothness",
                hint: "tune.smoothness_hint",
                valueText: "\(settings.oversampling)×",
                value: $settings.oversampling,
                range: 1...6,
                accessibilityValueText: "\(settings.oversampling)"
            )

            Toggle("tune.invert", isOn: $settings.invert)
                .font(DWFont.label)
                .foregroundStyle(DWColor.text)
                .tint(DWColor.cyan)
        }
    }

    // MARK: - Advanced

    private var advanced: some View {
        VStack(alignment: .leading, spacing: DWSpace.m) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: DWSpace.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("tune.advanced")
                            .font(DWFont.label)
                            .foregroundStyle(DWColor.text)
                        Text("tune.advanced_subtitle")
                            .font(DWFont.mono(9.5))
                            .foregroundStyle(DWColor.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DWColor.textSecondary)
                        .rotationEffect(.degrees(showAdvanced ? 180 : 0))
                }
                .padding(.horizontal, DWSpace.l)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dwGlass(radius: DWRadius.lg)

            if showAdvanced {
                VStack(alignment: .leading, spacing: DWSpace.l) {
                    DWSliderRow(
                        title: "tune.dpi",
                        hint: "tune.dpi_hint",
                        valueText: "\(settings.dpi)",
                        value: $settings.dpi,
                        range: 60...150,
                        accessibilityValueText: "\(settings.dpi)"
                    )

                    if depthMap != nil {
                        DWGroupedList {
                            DWListRow(
                                title: "tune.depth_ranges",
                                subtitle: "tune.depth_ranges_subtitle",
                                systemImage: "slider.horizontal.below.square.and.square.filled",
                                tint: DWColor.periwinkle
                            ) {
                                path.append(NavigationDestination.depthAdjustment)
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
#endif
