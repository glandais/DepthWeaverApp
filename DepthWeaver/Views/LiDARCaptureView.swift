import ARKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.glandais.DepthWeaver", category: "LiDARCaptureView")

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
        .navigationTitle("LiDAR Scan")
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

            Text("Camera Access Required")
                .font(.title2)
                .fontWeight(.bold)

            Text("DepthWeaver uses your camera and LiDAR sensor to capture 3D depth information of your surroundings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start Scanning") {
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

            Text("Camera Access Denied")
                .font(.title2)
                .fontWeight(.bold)

            Text("Please enable camera access in Settings to use LiDAR scanning.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Open Settings") {
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
                ARCameraPreview(cameraImage: depthService.cameraImage)
                    .frame(width: geo.size.width, height: geo.size.height)

                VStack {
                    if !depthService.hasDepthData {
                        Text("Waiting for depth data...")
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
                    .accessibilityLabel("Capture depth")
                    .accessibilityHint("Takes a depth snapshot of the current scene")
                    .padding(.bottom, 16)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .animation(.smooth(duration: 0.4), value: depthService.hasDepthData)
            }
        }
        .ignoresSafeArea()
    }
}

/// Simple camera preview driven by a published UIImage from the depth service.
struct ARCameraPreview: View {
    let cameraImage: UIImage?

    var body: some View {
        if let cameraImage {
            Image(uiImage: cameraImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.black
        }
    }
}
