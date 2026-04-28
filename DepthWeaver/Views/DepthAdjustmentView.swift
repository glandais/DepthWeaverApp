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
            VStack(spacing: 20) {
                if let dm = depthMap {
                    DepthPointCloudView(depthMap: dm, adjustment: adjustment)
                        .aspectRatio(CGFloat(dm.width) / CGFloat(dm.height), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if depthMap?.source == .imported {
                    GroupBox(String(localized: "depth_adjustment.denoising", comment: "Depth adjustment section")) {
                        VStack(spacing: 16) {
                            HStack {
                                Toggle(String(localized: "depth_adjustment.denoising.enable", comment: "Denoising toggle"), isOn: $denoising.enabled)
                                if isDenoising {
                                    ProgressView().controlSize(.small)
                                }
                            }

                            if denoising.enabled {
                                VStack(alignment: .leading) {
                                    Text("depth_adjustment.denoising.bilateral \(denoising.bilateralIntensity, specifier: "%.2f")")
                                        .font(.subheadline)
                                    Slider(value: $denoising.bilateralIntensity, in: 0...1)
                                }

                                VStack(alignment: .leading) {
                                    Text("depth_adjustment.denoising.morphology \(denoising.morphologyRadius, specifier: "%.0f")")
                                        .font(.subheadline)
                                    Slider(value: $denoising.morphologyRadius, in: 0...8, step: 1)
                                }

                                VStack(alignment: .leading) {
                                    Text("depth_adjustment.denoising.background \(denoising.backgroundThreshold, specifier: "%.3f")")
                                        .font(.subheadline)
                                    Slider(value: $denoising.backgroundThreshold, in: 0...0.5)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Input range
                GroupBox(String(localized: "depth_adjustment.input_range", comment: "Depth adjustment section")) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("depth_adjustment.min_value \(adjustment.min, specifier: "%.3f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.min,
                                in: rawRange
                            )
                        }

                        VStack(alignment: .leading) {
                            Text("depth_adjustment.max_value \(adjustment.max, specifier: "%.3f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.max,
                                in: rawRange
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Output range
                // For LiDAR, start/end are inverted internally (start=1, end=0).
                // Display "Start" editing `end` and "End" editing `start` so labels match user expectation.
                GroupBox(String(localized: "depth_adjustment.output_range", comment: "Depth adjustment section")) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("depth_adjustment.start_value \(adjustment.start, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.end,
                                in: 0...1
                            )
                        }

                        VStack(alignment: .leading) {
                            Text("depth_adjustment.end_value \(adjustment.end, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.start,
                                in: 0...1
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button("depth_adjustment.reset") {
                    guard let dm = depthMap else { return }
                    adjustment = DepthMap.initialAdjustment(rawDepth: dm.originalDepth)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
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
