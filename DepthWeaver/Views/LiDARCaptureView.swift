#if os(iOS)
import ARKit
import os
import SwiftUI

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "LiDARCaptureView")

struct LiDARCaptureView: View {
    @ObservedObject var depthService: LiDARDepthService
    let onCapture: (DepthMap) -> Void
    @StateObject private var viewModel = LiDARCaptureViewModel()

    var body: some View {
        Group {
            switch viewModel.cameraPermission {
            case .notDetermined:
                prePermissionView
            case .denied:
                permissionDeniedView
            case .authorized:
                captureView
            }
        }
        .navigationTitle("depth.lidar_scan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.checkPermission()
            if viewModel.cameraPermission == .authorized && !depthService.isRunning {
                depthService.start()
            }
        }
    }

    private var prePermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.metering.matrix")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("lidar.camera_required")
                .font(.title2)
                .fontWeight(.bold)

            Text("lidar.camera_description")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("lidar.start_scanning") {
                Task {
                    await viewModel.requestPermission()
                    if viewModel.cameraPermission == .authorized {
                        depthService.start()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(32)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("lidar.camera_denied")
                .font(.title2)
                .fontWeight(.bold)

            Text("lidar.enable_camera")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("lidar.open_settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var captureView: some View {
        GeometryReader { geo in
            ZStack {
                ARDepthPreview(depthImage: depthService.depthPreviewImage)
                    .frame(width: geo.size.width, height: geo.size.height)

                VStack {
                    if !depthService.hasDepthData {
                        Text("lidar.waiting_for_depth")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer()

                    Button {
                        logger.info("Capture button tapped")
                        if let depthMap = depthService.captureCurrentDepth() {
                            logger.info("Got depth map \(depthMap.width)x\(depthMap.height), calling onCapture")
                            onCapture(depthMap)
                        } else {
                            logger.error("captureCurrentDepth() returned nil")
                        }
                    } label: {
                        Image(systemName: "camera.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white)
                            .shadow(radius: 4)
                    }
                    .disabled(!depthService.hasDepthData)
                    .animation(.smooth) { content in
                        content.opacity(depthService.hasDepthData ? 1.0 : 0.5)
                    }
                    .accessibilityLabel("lidar.capture_depth")
                    .accessibilityHint("lidar.capture_hint")
                    .padding(.bottom, 16)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.smooth(duration: 0.4), value: depthService.hasDepthData)
            }
        }
        .ignoresSafeArea()
    }
}

/// Live hue-mapped depth visualization driven by a published UIImage from the depth service.
struct ARDepthPreview: View {
    let depthImage: UIImage?

    var body: some View {
        if let depthImage {
            Image(uiImage: depthImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.black
        }
    }
}

#endif
