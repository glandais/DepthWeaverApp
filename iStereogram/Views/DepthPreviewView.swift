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
                                in: 60...300,
                                step: 1
                            )
                            .accessibilityLabel("Strip width")
                            .accessibilityValue("\(settings.stripWidth) pixels")
                        }

                        VStack(alignment: .leading) {
                            Text("Eye Separation: \(settings.eyeSeparation)")
                                .font(.subheadline)
                            Slider(
                                value: Binding(
                                    get: { Double(settings.eyeSeparation) },
                                    set: { settings.eyeSeparation = Int($0) }
                                ),
                                in: 40...120,
                                step: 1
                            )
                            .accessibilityLabel("Eye separation")
                            .accessibilityValue("\(settings.eyeSeparation) pixels")
                        }

                        Toggle("Invert Depth", isOn: $settings.invert)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }

                // Generate button
                Button {
                    Task {
                        await stereogramVM.generate(depthMap: depthMap, settings: settings)
                        if let image = stereogramVM.resultImage {
                            path.append(NavigationDestination.stereogramResult(image))
                        }
                    }
                } label: {
                    Label("Generate Stereogram", systemImage: "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(stereogramVM.isGenerating)
                .accessibilityHint("Creates an autostereogram from the depth map")
            }
            .padding()
        }
        .navigationTitle("Depth Map")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if stereogramVM.isGenerating {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Generating stereogram...")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
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
}
