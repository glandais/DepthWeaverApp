import os
import SwiftUI

private let logger = Logger(subsystem: "com.glandais.iStereogram", category: "DepthPreviewView")

struct DepthPreviewView: View {
    let depthMap: DepthMap
    @Binding var path: NavigationPath

    @State private var settings = StereogramSettings()
    @StateObject private var stereogramVM = StereogramViewModel()

    var body: some View {
        let _ = logger.info("DepthPreviewView body evaluated, depthMap \(depthMap.width)x\(depthMap.height)")
        ScrollView {
            VStack(spacing: 20) {
                Text("Depth: \(depthMap.width)x\(depthMap.height) (\(depthMap.source == .lidar ? "LiDAR" : "AI"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Depth map preview
                depthMapPreview
                    .accessibilityLabel("Depth map preview")

                // Pattern picker
                GroupBox("Pattern") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(StereogramPattern.allCases) { pattern in
                                Button {
                                    settings.pattern = pattern
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(uiImage: pattern.loadImage())
                                            .resizable()
                                            .interpolation(.none)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(settings.pattern == pattern ? Color.blue : Color.clear, lineWidth: 3)
                                            )

                                        Text(pattern.displayName)
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(pattern.displayName)
                                .accessibilityAddTraits(settings.pattern == pattern ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Settings
                GroupBox("Settings") {
                    VStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("Strip Width: \(settings.stripWidth)")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.stripWidth) },
                                    set: { settings.stripWidth = Int($0) }
                                ),
                                in: 80...200,
                                step: 10
                            )
                            .accessibilityLabel("Strip width")
                            .accessibilityValue("\(settings.stripWidth) pixels")
                        }

                        VStack(alignment: .leading) {
                            Text("Depth Amplitude: \(settings.depthAmplitude, specifier: "%.2f")")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.depthAmplitude) },
                                    set: { settings.depthAmplitude = Float($0) }
                                ),
                                in: 0.05...0.6,
                                step: 0.01
                            )
                            .accessibilityLabel("Depth amplitude")
                            .accessibilityValue("\(settings.depthAmplitude, specifier: "%.2f")")
                        }

                        Toggle("Invert Depth", isOn: $settings.invert)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }

                // Stereogram preview
                stereogramPreview
            }
            .padding()
        }
        .navigationTitle("Depth Map")
        .navigationBarTitleDisplayMode(.inline)
        .allowsHitTesting(!stereogramVM.isGenerating)
        .overlay {
            if stereogramVM.isGenerating {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .onAppear {
            stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
        }
        .onChange(of: settings.stripWidth) { _, _ in
            stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
        }
        .onChange(of: settings.depthAmplitude) { _, _ in
            stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
        }
        .onChange(of: settings.invert) { _, _ in
            stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
        }
        .onChange(of: settings.pattern) { _, _ in
            stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
        }
    }

    @ViewBuilder
    private var depthMapPreview: some View {
        if let uiImage = depthMap.previewImage() {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ContentUnavailableView("Could not render depth map", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var stereogramPreview: some View {
        if let image = stereogramVM.resultImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    path.append(NavigationDestination.stereogramResult(image))
                }
                .accessibilityLabel("Stereogram preview")
                .accessibilityHint("Tap to view full screen")
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .aspectRatio(CGFloat(depthMap.width) / CGFloat(depthMap.height), contentMode: .fit)
                .overlay {
                    if stereogramVM.isGenerating {
                        ProgressView("Generating...")
                    } else {
                        Text("Stereogram")
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }
}
