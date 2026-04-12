import SwiftUI

struct DepthAdjustmentView: View {
    @Binding var depthMap: DepthMap?

    @State private var adjustment: DepthAdjustment = DepthAdjustment()
    @State private var rawRange: ClosedRange<Float> = 0...1

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let dm = depthMap {
                    DepthPointCloudView(depthMap: dm, adjustment: adjustment)
                        .aspectRatio(CGFloat(dm.width) / CGFloat(dm.height), contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                                value: $adjustment.start,
                                in: 0...1
                            )
                        }

                        VStack(alignment: .leading) {
                            Text("depth_adjustment.end_value \(adjustment.end, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.end,
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
    }
}
