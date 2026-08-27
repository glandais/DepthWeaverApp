#if os(iOS)
import SwiftUI

struct DepthAdjustmentView: View {
    @Binding var depthMap: DepthMap?

    @State private var adjustment: DepthAdjustment = DepthAdjustment()
    @State private var rawRange: ClosedRange<Float> = 0...1
    @State private var denoising: DepthDenoising = DepthDenoising()
    @State private var denoiseTask: Task<Void, Never>?
    @State private var isDenoising: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DWSpace.xl) {
                if let dm = depthMap {
                    DepthPointCloudView(depthMap: dm, adjustment: adjustment)
                        .aspectRatio(CGFloat(dm.width) / CGFloat(dm.height), contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: DWRadius.lg, style: .continuous))
                }

                if depthMap?.source == .imported {
                    denoisingSection
                }

                inputRange
                outputRange

                Button("depth_adjustment.reset") {
                    guard let dm = depthMap else { return }
                    adjustment = DepthMap.initialAdjustment(rawDepth: dm.originalDepth)
                }
                .buttonStyle(DWGlassButtonStyle())
            }
            .padding(DWSpace.l)
            .padding(.bottom, DWSpace.section)
        }
        .background(DWColor.ground)
        // The sliders are custom drag controls, so one sitting over the home
        // indicator would hand its first swipe to the app switcher instead.
        .defersSystemGestures(on: .bottom)
        .navigationTitle(String(localized: "depth.adjust_depth", comment: "Navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let dm = depthMap else { return }
            adjustment = dm.adjustment
            rawRange = dm.rawDepthRange
            denoising = dm.denoising
        }
        .onChange(of: adjustment) { _, newValue in
            // Enforce max > min
            var adj = newValue
            if adj.max <= adj.min {
                adj.max = adj.min + (rawRange.upperBound - rawRange.lowerBound) * 0.001
            }
            if adj != newValue {
                adjustment = adj
                return
            }
            depthMap?.adjustment = adj
        }
        .onChange(of: denoising) { _, newValue in
            scheduleDenoising(newValue)
        }
        .onDisappear {
            denoiseTask?.cancel()
        }
    }

    // MARK: - Sections

    private var denoisingSection: some View {
        VStack(alignment: .leading, spacing: DWSpace.l) {
            HStack(spacing: DWSpace.s) {
                DWSectionLabel("depth_adjustment.denoising")
                if isDenoising {
                    ProgressView().controlSize(.small).tint(DWColor.cyan)
                }
            }

            Toggle(
                String(localized: "depth_adjustment.denoising.enable", comment: "Denoising toggle"),
                isOn: $denoising.enabled
            )
            .font(DWFont.label)
            .foregroundStyle(DWColor.text)
            .tint(DWColor.cyan)

            if denoising.enabled {
                DWSliderRow(
                    title: "depth_adjustment.denoising.bilateral_label",
                    valueText: String(format: "%.2f", denoising.bilateralIntensity),
                    value: $denoising.bilateralIntensity,
                    range: 0...1
                )
                DWSliderRow(
                    title: "depth_adjustment.denoising.morphology_label",
                    valueText: String(format: "%.0f", denoising.morphologyRadius),
                    value: $denoising.morphologyRadius,
                    range: 0...8,
                    step: 1
                )
                DWSliderRow(
                    title: "depth_adjustment.denoising.background_label",
                    valueText: String(format: "%.3f", denoising.backgroundThreshold),
                    value: $denoising.backgroundThreshold,
                    range: 0...0.5
                )
            }
        }
    }

    private var inputRange: some View {
        VStack(alignment: .leading, spacing: DWSpace.l) {
            DWSectionLabel("depth_adjustment.input_range")
            DWSliderRow(
                title: "depth_adjustment.min_label",
                valueText: String(format: "%.3f", adjustment.min),
                value: $adjustment.min,
                range: rawRange
            )
            DWSliderRow(
                title: "depth_adjustment.max_label",
                valueText: String(format: "%.3f", adjustment.max),
                value: $adjustment.max,
                range: rawRange
            )
        }
    }

    // For LiDAR, start/end are inverted internally (start=1, end=0).
    // Display "Start" editing `end` and "End" editing `start` so labels match
    // user expectation.
    private var outputRange: some View {
        VStack(alignment: .leading, spacing: DWSpace.l) {
            DWSectionLabel("depth_adjustment.output_range")
            DWSliderRow(
                title: "depth_adjustment.start_label",
                valueText: String(format: "%.2f", adjustment.start),
                value: $adjustment.end,
                range: 0...1
            )
            DWSliderRow(
                title: "depth_adjustment.end_label",
                valueText: String(format: "%.2f", adjustment.end),
                value: $adjustment.start,
                range: 0...1
            )
        }
    }

    private func scheduleDenoising(_ params: DepthDenoising) {
        guard let dm = depthMap, dm.source == .imported else { return }

        let prev = dm.denoising
        let onlyToggleChanged = prev.bilateralIntensity == params.bilateralIntensity
            && prev.morphologyRadius == params.morphologyRadius
            && prev.backgroundThreshold == params.backgroundThreshold

        if onlyToggleChanged {
            // Pure on/off: cached buffer (if any) stays valid for these params — flip instantly.
            denoiseTask?.cancel()
            isDenoising = false
            var current = dm
            current.setDenoising(params, denoisedDepth: current.denoisedDepth)
            depthMap = current
            rawRange = current.rawDepthRange
            return
        }

        // A slider moved — sliders are only visible when enabled, so params.enabled is true here.
        denoiseTask?.cancel()
        let originalDepth = dm.originalDepth
        let sw = dm.sourceWidth
        let sh = dm.sourceHeight
        isDenoising = true
        denoiseTask = Task.detached(priority: .userInitiated) {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
            let buffer = DepthMapDenoiser.shared.denoise(
                pixels: originalDepth, width: sw, height: sh, parameters: params
            )
            if Task.isCancelled { return }
            await MainActor.run {
                guard var current = depthMap, current.source == .imported else {
                    isDenoising = false
                    return
                }
                current.setDenoising(params, denoisedDepth: buffer)
                depthMap = current
                rawRange = current.rawDepthRange
                isDenoising = false
            }
        }
    }
}

#endif
