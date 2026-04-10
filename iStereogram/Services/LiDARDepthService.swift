import ARKit
import CoreImage
import os
import UIKit

private let logger = Logger(subsystem: "com.glandais.iStereogram", category: "LiDARDepthService")

final class LiDARDepthService: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var isRunning = false
    @Published var hasDepthData = false
    @Published var cameraImage: UIImage?
    private var frameCount = 0
    private var depthDetected = false
    private let ciContext = CIContext()

    static var isSupported: Bool {
        let supported = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        logger.info("LiDAR supported: \(supported)")
        return supported
    }

    override init() {
        super.init()
        session.delegate = self
        logger.info("LiDARDepthService initialized")
    }

    func start() {
        logger.info("start() called")
        guard LiDARDepthService.isSupported else {
            logger.error("LiDAR not supported, aborting start")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)
        session.run(config)
        isRunning = true
        frameCount = 0
        depthDetected = false
    }

    func pause() {
        session.pause()
        isRunning = false
        logger.info("ARSession paused after \(self.frameCount) frames")
    }

    func resume() {
        guard LiDARDepthService.isSupported else { return }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.sceneDepth)
        session.run(config)
        isRunning = true
        logger.info("ARSession resumed")
    }

    func captureCurrentDepth() -> DepthMap? {
        logger.info("captureCurrentDepth() called, frameCount=\(self.frameCount)")
        guard let currentFrame = session.currentFrame else {
            logger.error("session.currentFrame is nil")
            return nil
        }

        let sceneDepth = currentFrame.smoothedSceneDepth ?? currentFrame.sceneDepth
        guard let sceneDepth else {
            logger.error("Both smoothedSceneDepth and sceneDepth are nil")
            return nil
        }

        // The LiDAR depth buffer is always 256x192 (landscape).
        // Rotate it to match the device orientation at capture time.
        let srcBuffer = sceneDepth.depthMap
        let interfaceOrientation = UIDevice.current.orientation

        let width = CVPixelBufferGetWidth(srcBuffer)
        let height = CVPixelBufferGetHeight(srcBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(srcBuffer)
        logger.info("Depth buffer: \(width)x\(height), format=\(pixelFormat), deviceOrientation=\(interfaceOrientation.rawValue)")

        // Copy the depth buffer since ARKit reuses it
        var copiedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, nil, &copiedBuffer)
        guard status == kCVReturnSuccess, let dst = copiedBuffer else {
            logger.error("Failed to create copy buffer, status=\(status)")
            return nil
        }

        CVPixelBufferLockBaseAddress(srcBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        let srcData = CVPixelBufferGetBaseAddress(srcBuffer)!
        let dstData = CVPixelBufferGetBaseAddress(dst)!
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(srcBuffer)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(dst)
        for row in 0..<height {
            memcpy(dstData + row * dstBytesPerRow, srcData + row * srcBytesPerRow, min(srcBytesPerRow, dstBytesPerRow))
        }
        CVPixelBufferUnlockBaseAddress(dst, [])
        CVPixelBufferUnlockBaseAddress(srcBuffer, .readOnly)

        logger.info("Depth buffer copied successfully")

        // If portrait, rotate the depth buffer 90° CW
        if interfaceOrientation == .portrait || interfaceOrientation == .unknown {
            if let rotated = rotateDepthBuffer90CW(dst, width: width, height: height, pixelFormat: pixelFormat) {
                return DepthMap(pixelBuffer: rotated, source: .lidar, originalWidth: nil, originalHeight: nil)
            }
        } else if interfaceOrientation == .portraitUpsideDown {
            if let rotated = rotateDepthBuffer90CCW(dst, width: width, height: height, pixelFormat: pixelFormat) {
                return DepthMap(pixelBuffer: rotated, source: .lidar, originalWidth: nil, originalHeight: nil)
            }
        }

        return DepthMap(pixelBuffer: dst, source: .lidar, originalWidth: nil, originalHeight: nil)
    }

    /// Rotates a Float32 depth buffer 90° clockwise (landscape → portrait)
    private func rotateDepthBuffer90CW(_ src: CVPixelBuffer, width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer? {
        var rotated: CVPixelBuffer?
        // New dimensions: width becomes height, height becomes width
        let status = CVPixelBufferCreate(kCFAllocatorDefault, height, width, pixelFormat, nil, &rotated)
        guard status == kCVReturnSuccess, let dst = rotated else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        let srcPtr = CVPixelBufferGetBaseAddress(src)!.assumingMemoryBound(to: Float.self)
        let dstPtr = CVPixelBufferGetBaseAddress(dst)!.assumingMemoryBound(to: Float.self)
        let srcRowFloats = CVPixelBufferGetBytesPerRow(src) / MemoryLayout<Float>.size
        let dstRowFloats = CVPixelBufferGetBytesPerRow(dst) / MemoryLayout<Float>.size

        for y in 0..<height {
            for x in 0..<width {
                // (x,y) in source → (height-1-y, x) rotated, but for CW: (y, width-1-x) → no
                // CW rotation: dst(height-1-y, x) = src(x, y)
                // Actually: for 90° CW, new(x', y') where x' = height-1-y, y' = x
                let dstX = height - 1 - y
                let dstY = x
                dstPtr[dstY * dstRowFloats + dstX] = srcPtr[y * srcRowFloats + x]
            }
        }
        CVPixelBufferUnlockBaseAddress(dst, [])
        CVPixelBufferUnlockBaseAddress(src, .readOnly)
        return dst
    }

    /// Rotates a Float32 depth buffer 90° counter-clockwise
    private func rotateDepthBuffer90CCW(_ src: CVPixelBuffer, width: Int, height: Int, pixelFormat: OSType) -> CVPixelBuffer? {
        var rotated: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, height, width, pixelFormat, nil, &rotated)
        guard status == kCVReturnSuccess, let dst = rotated else { return nil }

        CVPixelBufferLockBaseAddress(src, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        let srcPtr = CVPixelBufferGetBaseAddress(src)!.assumingMemoryBound(to: Float.self)
        let dstPtr = CVPixelBufferGetBaseAddress(dst)!.assumingMemoryBound(to: Float.self)
        let srcRowFloats = CVPixelBufferGetBytesPerRow(src) / MemoryLayout<Float>.size
        let dstRowFloats = CVPixelBufferGetBytesPerRow(dst) / MemoryLayout<Float>.size

        for y in 0..<height {
            for x in 0..<width {
                let dstX = y
                let dstY = width - 1 - x
                dstPtr[dstY * dstRowFloats + dstX] = srcPtr[y * srcRowFloats + x]
            }
        }
        CVPixelBufferUnlockBaseAddress(dst, [])
        CVPixelBufferUnlockBaseAddress(src, .readOnly)
        return dst
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        let hasSmoothed = frame.smoothedSceneDepth != nil
        let hasRaw = frame.sceneDepth != nil

        if frameCount <= 5 || frameCount % 100 == 0 {
            logger.info("Frame #\(self.frameCount), smoothedSceneDepth=\(hasSmoothed), sceneDepth=\(hasRaw)")
        }

        let newHasDepth = hasSmoothed || hasRaw

        if newHasDepth && !depthDetected {
            depthDetected = true
            logger.info("Depth data became available at frame #\(self.frameCount)")
        }

        // Use device orientation to determine correct image rotation
        let ciImage = CIImage(cvPixelBuffer: frame.capturedImage)
        let oriented: CIImage
        let deviceOrientation = UIDevice.current.orientation
        switch deviceOrientation {
        case .landscapeLeft:
            oriented = ciImage.oriented(.up)
        case .landscapeRight:
            oriented = ciImage.oriented(.down)
        case .portraitUpsideDown:
            oriented = ciImage.oriented(.left)
        default: // portrait or unknown
            oriented = ciImage.oriented(.right)
        }

        // Render camera preview (throttle to ~30fps — every other frame)
        if frameCount % 2 == 0 {
            if let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                let detected = depthDetected
                DispatchQueue.main.async {
                    self.cameraImage = uiImage
                    self.hasDepthData = detected
                }
            }
        } else if depthDetected {
            // Ensure hasDepthData gets set even on odd frames
            DispatchQueue.main.async {
                if !self.hasDepthData {
                    self.hasDepthData = true
                }
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        logger.error("ARSession failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        logger.warning("ARSession was interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        logger.info("ARSession interruption ended")
    }
}
