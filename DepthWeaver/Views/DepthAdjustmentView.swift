import SwiftUI

struct DepthAdjustmentView: View {
    @Binding var depthMap: DepthMap?

    @State private var adjustment: DepthAdjustment = DepthAdjustment()
    @State private var previewImage: UIImage?
    @State private var previewImageHighlighted: UIImage?
    @State private var rawRange: ClosedRange<Float> = 0...1
    @State private var showHighlight = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live preview with blinking clamped pixels
                ZStack {
                    if let image = previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                    }
                    if let highlighted = previewImageHighlighted {
                        Image(uiImage: highlighted)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .opacity(showHighlight ? 1 : 0)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Input range
                GroupBox(String(localized: "Input Range", comment: "Depth adjustment section")) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Min: \(adjustment.min, specifier: "%.3f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.min,
                                in: rawRange
                            )
                        }

                        VStack(alignment: .leading) {
                            Text("Max: \(adjustment.max, specifier: "%.3f")")
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
                GroupBox(String(localized: "Output Range", comment: "Depth adjustment section")) {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Start: \(adjustment.start, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.start,
                                in: 0...1
                            )
                        }

                        VStack(alignment: .leading) {
                            Text("End: \(adjustment.end, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: $adjustment.end,
                                in: 0...1
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button("Reset") {
                    guard let dm = depthMap else { return }
                    adjustment = DepthMap.initialAdjustment(rawDepth: dm.originalDepth)
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle(String(localized: "Adjust Depth", comment: "Navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let dm = depthMap else { return }
            adjustment = dm.adjustment
            rawRange = dm.rawDepthRange
            updatePreview()
            startBlinking()
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
            updatePreview()
        }
    }

    private func updatePreview() {
        guard let dm = depthMap else { return }
        previewImage = dm.previewImage()
        previewImageHighlighted = dm.previewImage(highlightClamped: true)
    }

    private func startBlinking() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
            showHighlight = true
        }
    }
}
