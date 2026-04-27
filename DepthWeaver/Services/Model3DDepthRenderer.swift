import CoreVideo
import Metal
import os
import SceneKit

private let logger = Logger(subsystem: "com.glandais.DepthWeaver", category: "Model3DDepthRenderer")

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

        // Color attachment is required even if we only consume depth.
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
        passDescriptor.colorAttachments[0].storeAction = .dontCare
        passDescriptor.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
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
        let bytesPerRow = width * MemoryLayout<Float>.size
        ndcValues.withUnsafeMutableBytes { rawBuf in
            stagingDepthTex.getBytes(
                rawBuf.baseAddress!,
                bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // Linearize. Metal's depth32Float NDC is [0,1] with 1 = far plane.
        // For a perspective projection with infinite z reversed-Z handling not in use here,
        // linear view-space distance is: z = (near * far) / (far - z_ndc * (far - near)).
        // Treat z_ndc == 1.0 (background after clear) as NaN so it's ignored downstream.
        let denomSpan = far - near
        var linear = [Float](repeating: .nan, count: pixelCount)
        for i in 0..<pixelCount {
            let z = ndcValues[i]
            if z >= 0.99999 {
                linear[i] = .nan
            } else {
                let denom = far - z * denomSpan
                if denom > 0 {
                    linear[i] = (near * far) / denom
                } else {
                    linear[i] = .nan
                }
            }
        }

        guard let pixelBuffer = makeFloat32PixelBuffer(width: width, height: height, values: linear) else {
            logger.error("captureDepthMap: failed to build pixel buffer")
            return nil
        }

        var depthMap = DepthMap(
            pixelBuffer: pixelBuffer,
            source: .imported,
            originalWidth: width,
            originalHeight: height
        )
        // Same convention as DepthMapPreset.toDepthMap(): closer = brighter (subject pops out).
        depthMap.adjustment.start = 1
        depthMap.adjustment.end = 0
        return depthMap
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
