#if os(iOS)
/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Top-level SwiftUI container for the guided 3D capture flow.
Adapted from Apple's GuidedCapture sample for use inside DepthWeaver:
the original `ContentView` is renamed to `GuidedCaptureRootView` and a
`onCompleted` callback fires once the reconstructed `.usdz` lands on disk.
*/

import RealityKit
import SwiftUI
import os

@available(iOS 17.0, *)
struct GuidedCaptureRootView: View {
    static let logger = Logger(subsystem: "io.github.glandais.depthweaver",
                                category: "GuidedCaptureRootView")

    let onCompleted: (URL) -> Void

    @StateObject var appModel: GuidedCaptureModel = GuidedCaptureModel.instance

    @State private var showReconstructionView: Bool = false
    @State private var showErrorAlert: Bool = false
    @State private var didDeliverURL: Bool = false
    private var showProgressView: Bool {
        appModel.state == .completed || appModel.state == .restart || appModel.state == .ready
    }

    var body: some View {
        VStack {
            if appModel.state == .capturing {
                if let session = appModel.objectCaptureSession {
                    CapturePrimaryView(session: session)
                }
            } else if showProgressView {
                CircularProgressView()
            }
        }
        .onChange(of: appModel.state) { _, newState in
            if newState == .failed {
                showErrorAlert = true
                showReconstructionView = false
            } else {
                showErrorAlert = false
                showReconstructionView = newState == .reconstructing || newState == .viewing
            }
            deliverIfReady(state: newState)
        }
        .sheet(isPresented: $showReconstructionView) {
            if let folderManager = appModel.scanFolderManager {
                ReconstructionPrimaryView(outputFile: folderManager.rootScanFolder.appendingPathComponent("model-mobile.usdz"))
            }
        }
        .alert(
            "Failed:  " + (appModel.error != nil  ? "\(String(describing: appModel.error!))" : ""),
            isPresented: $showErrorAlert,
            actions: {
                Button("OK") {
                    Self.logger.log("Calling restart...")
                    appModel.state = .restart
                }
            },
            message: {}
        )
        .environmentObject(appModel)
    }

    private func deliverIfReady(state: GuidedCaptureModel.ModelState) {
        guard !didDeliverURL,
              state == .viewing || state == .completed,
              let folder = appModel.scanFolderManager else { return }
        let usdz = folder.rootScanFolder.appendingPathComponent("model-mobile.usdz")
        guard FileManager.default.fileExists(atPath: usdz.path) else { return }
        didDeliverURL = true
        onCompleted(usdz)
    }
}

private struct CircularProgressView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack {
            Spacer()
            ZStack {
                Spacer()
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .light ? .black : .white))
                Spacer()
            }
            Spacer()
        }
    }
}

#endif
