import CoreVideo
import Metal
import os
import SceneKit

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "Model3DDepthRenderer")

enum Model3DDepthRenderer {
    /// Renders the scene currently displayed in `scnView` from the user's framed
    /// camera into a `DepthMap` of the requested pixel size.
    ///
    /// The depth values stored are linear view-space distances in scene units
    /// (meters when the scene uses meter conventions). Cleared/background pixels
    /// are written as `Float.nan` so `DepthMap.initialAdjustment` ignores them
    /// when computing the auto range.
    static func captureDepthMap(from scnView: SCNView, outputSize: CGSize) -> DepthMap? {
        let width = max(1, Int(outputSize.width.rounded()))
        let height = max(1, Int(outputSize.height.rounded()))

        guard let scene = scnView.scene else {
            logger.error("captureDepthMap: scnView has no scene")
            return nil
        }
        guard let pov = scnView.pointOfView, let camera = pov.camera else {
            logger.error("captureDepthMap: scnView has no pointOfView/camera")
            return nil
        }
        guard let device = scnView.device ?? MTLCreateSystemDefaultDevice() else {
            logger.error("captureDepthMap: no Metal device")
            return nil
        }
        guard let commandQueue = device.makeCommandQueue() else {
            logger.error("captureDepthMap: failed to create command queue")
            return nil
        }

        let near = Float(camera.zNear)
        let far = Float(camera.zFar)

        // Color attachment doubles as our background mask: cleared to alpha=0,
        // opaque geometry writes alpha=1, so any pixel that comes back with
        // alpha == 0 was never drawn and gets a NaN depth downstream. This is
        // more robust than relying on the depth-buffer clear value, since
        // SCNRenderer can use reversed-Z internally and override our clearDepth.
        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        colorDesc.usage = [.renderTarget, .shaderRead]
        colorDesc.storageMode = .private
        guard let colorTex = device.makeTexture(descriptor: colorDesc) else {
            logger.error("captureDepthMap: failed to allocate color texture")
            return nil
        }

        let colorStagingDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        colorStagingDesc.usage = [.shaderRead]
        colorStagingDesc.storageMode = .shared
        guard let stagingColorTex = device.makeTexture(descriptor: colorStagingDesc) else {
            logger.error("captureDepthMap: failed to allocate staging color texture")
            return nil
        }

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.storageMode = .private
        guard let privateDepthTex = device.makeTexture(descriptor: depthDesc) else {
            logger.error("captureDepthMap: failed to allocate depth texture")
            return nil
        }

        let stagingDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        stagingDesc.usage = [.shaderRead]
        stagingDesc.storageMode = .shared
        guard let stagingDepthTex = device.makeTexture(descriptor: stagingDesc) else {
            logger.error("captureDepthMap: failed to allocate staging texture")
            return nil
        }

        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = colorTex
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].storeAction = .store
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        passDescriptor.depthAttachment.texture = privateDepthTex
        passDescriptor.depthAttachment.loadAction = .clear
        passDescriptor.depthAttachment.storeAction = .store
        passDescriptor.depthAttachment.clearDepth = 1.0

        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = pov

        guard let cmdBuf = commandQueue.makeCommandBuffer() else {
            logger.error("captureDepthMap: failed to create command buffer")
            return nil
        }

        let viewport = CGRect(x: 0, y: 0, width: width, height: height)
        renderer.render(atTime: 0, viewport: viewport, commandBuffer: cmdBuf, passDescriptor: passDescriptor)

        guard let blitEncoder = cmdBuf.makeBlitCommandEncoder() else {
            logger.error("captureDepthMap: failed to create blit encoder")
            return nil
        }
        blitEncoder.copy(
            from: privateDepthTex,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: stagingDepthTex,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.copy(
            from: colorTex,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: stagingColorTex,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let error = cmdBuf.error {
            logger.error("captureDepthMap: command buffer error: \(error.localizedDescription)")
            return nil
        }

        // Read NDC depth values out of the staging texture.
        let pixelCount = width * height
        var ndcValues = [Float](repeating: 1.0, count: pixelCount)
        let depthBytesPerRow = width * MemoryLayout<Float>.size
        ndcValues.withUnsafeMutableBytes { rawBuf in
            stagingDepthTex.getBytes(
                rawBuf.baseAddress!,
                bytesPerRow: depthBytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        var colorBytes = [UInt8](repeating: 0, count: pixelCount * 4)
        let colorBytesPerRow = width * 4
        colorBytes.withUnsafeMutableBytes { rawBuf in
            stagingColorTex.getBytes(
                rawBuf.baseAddress!,
                bytesPerRow: colorBytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // Background pixels are detected via the color attachment's alpha
        // (cleared to 0, opaque geometry writes 1). We sample the NDC of those
        // cleared pixels to figure out which depth convention SCNRenderer is
        // using: standard-Z clears to ~1 (far plane), reversed-Z clears to ~0.
        // SceneKit on modern Metal uses reversed-Z, so that's also our fallback
        // when the frame has no visible background.
        var clearedZSum: Float = 0
        var clearedZCount = 0
        for i in 0..<pixelCount where colorBytes[i * 4 + 3] == 0 {
            clearedZSum += ndcValues[i]
            clearedZCount += 1
            if clearedZCount >= 256 { break }
        }
        let isReversedZ = clearedZCount == 0 || (clearedZSum / Float(clearedZCount)) < 0.5

        // Linearize with the matching formula. Both produce view-space distance
        // in scene units, with smaller values = closer to camera.
        //   Standard-Z:  t = near·far / (far - z·(far-near))
        //   Reversed-Z:  t = near·far / (near + z·(far-near))
        let denomSpan = far - near
        var linear = [Float](repeating: .nan, count: pixelCount)
        var fgNdcMin: Float = .greatestFiniteMagnitude
        var fgNdcMax: Float = -.greatestFiniteMagnitude
        var fgCount = 0
        for i in 0..<pixelCount {
            if colorBytes[i * 4 + 3] == 0 {
                linear[i] = .nan
                continue
            }
            let z = ndcValues[i]
            fgNdcMin = Swift.min(fgNdcMin, z)
            fgNdcMax = Swift.max(fgNdcMax, z)
            fgCount += 1

            let denom: Float = isReversedZ ? (near + z * denomSpan) : (far - z * denomSpan)
            if denom > 0 {
                linear[i] = (near * far) / denom
            } else {
                linear[i] = .nan
            }
        }
        logger.info("captureDepthMap: zNear=\(near) zFar=\(far) fgPixels=\(fgCount) ndcRange=\(fgNdcMin)...\(fgNdcMax) reversedZ=\(isReversedZ)")

        // Push background pixels to a depth slightly behind the deepest visible
        // geometry so they sit clearly behind the subject in the stereogram
        // instead of inheriting the (undefined) NaN handling downstream or
        // merging with the farthest visible surface. The 25% padding keeps the
        // subject expressive while still leaving an obvious gap.
        var linMin: Float = .greatestFiniteMagnitude
        var linMax: Float = -.greatestFiniteMagnitude
        for v in linear where v.isFinite {
            if v < linMin { linMin = v }
            if v > linMax { linMax = v }
        }
        if linMin < linMax {
            let backgroundDepth = linMax + 0.25 * (linMax - linMin)
            for i in 0..<linear.count where !linear[i].isFinite {
                linear[i] = backgroundDepth
            }
        }

        guard let pixelBuffer = makeFloat32PixelBuffer(width: width, height: height, values: linear) else {
            logger.error("captureDepthMap: failed to build pixel buffer")
            return nil
        }

        // Linearization yields LiDAR-convention values (smaller = closer in
        // scene), so the default adjustment from `initialAdjustment` already
        // makes closer subjects pop out — no manual start/end override needed.
        return DepthMap(
            pixelBuffer: pixelBuffer,
            source: .model3D,
            originalWidth: width,
            originalHeight: height
        )
    }

    private static func makeFloat32PixelBuffer(width: Int, height: Int, values: [Float]) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_DepthFloat32,
            attrs as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pb = buffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let rowFloats = bytesPerRow / MemoryLayout<Float>.size

        values.withUnsafeBufferPointer { src in
            let dst = base.assumingMemoryBound(to: Float.self)
            for y in 0..<height {
                let srcOffset = y * width
                let dstOffset = y * rowFloats
                for x in 0..<width {
                    dst[dstOffset + x] = src[srcOffset + x]
                }
            }
        }
        return pb
    }
}
