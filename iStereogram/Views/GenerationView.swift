import os
import PhotosUI
import SwiftUI

private let logger = Logger(subsystem: "com.glandais.iStereogram", category: "GenerationView")

struct GenerationView: View {
    let depthMap: DepthMap?
    @Binding var path: NavigationPath
    @Binding var selectedPhoto: PhotosPickerItem?
    let lidarAvailable: Bool

    @State private var settings = StereogramSettings()
    @StateObject private var stereogramVM = StereogramViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Depth source section
                depthSourceSection

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
                                in: 80...300,
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
        .navigationTitle("iStereogram")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: depthMap?.id) { _, _ in
            triggerGeneration()
        }
        .onChange(of: settings.stripWidth) { _, _ in
            triggerGeneration()
        }
        .onChange(of: settings.depthAmplitude) { _, _ in
            triggerGeneration()
        }
        .onChange(of: settings.invert) { _, _ in
            triggerGeneration()
        }
        .onChange(of: settings.pattern) { _, _ in
            triggerGeneration()
        }
    }

    private func triggerGeneration() {
        guard let depthMap else {
            stereogramVM.resultImage = nil
            return
        }
        stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
    }

    // MARK: - Depth Source

    @ViewBuilder
    private var depthSourceSection: some View {
        if let depthMap {
            GroupBox {
                VStack(spacing: 12) {
                    HStack {
                        if let uiImage = depthMap.previewImage() {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Label(
                                depthMap.source == .lidar ? "LiDAR" : "AI",
                                systemImage: depthMap.source == .lidar ? "camera.metering.matrix" : "photo.on.rectangle"
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            Text("\(depthMap.width) × \(depthMap.height)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    depthAcquisitionButtons
                }
            } label: {
                Text("Depth Map")
            }
        } else {
            GroupBox {
                VStack(spacing: 16) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Acquire a depth map to generate stereograms")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    depthAcquisitionButtons
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } label: {
                Text("Depth Map")
            }
        }
    }

    @ViewBuilder
    private var depthAcquisitionButtons: some View {
        HStack(spacing: 12) {
            if lidarAvailable {
                Button {
                    path.append(NavigationDestination.lidarCapture)
                } label: {
                    Label("LiDAR Scan", systemImage: "camera.metering.matrix")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("From Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Stereogram Preview

    @ViewBuilder
    private var stereogramPreview: some View {
        if let image = stereogramVM.resultImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    if stereogramVM.isGenerating {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.ultraThinMaterial.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .onTapGesture {
                    if !stereogramVM.isGenerating {
                        path.append(NavigationDestination.stereogramResult(image))
                    }
                }
                .accessibilityLabel("Stereogram preview")
                .accessibilityHint("Tap to view full screen")
        } else if depthMap != nil {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .aspectRatio(CGFloat(depthMap!.width) / CGFloat(depthMap!.height), contentMode: .fit)
                .overlay {
                    ProgressView("Generating...")
                }
        }
    }
}
