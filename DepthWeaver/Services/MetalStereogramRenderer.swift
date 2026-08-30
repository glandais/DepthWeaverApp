import CoreGraphics
import Foundation
import Metal

/// GPU implementation of the stereogram algorithm.
/// One thread per output row; per-row scratch buffers are slices of large
/// device-memory arrays so the kernel can run with no synchronization.
final class MetalStereogramRenderer {
    static let shared = MetalStereogramRenderer()

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState

    /// Layout matching the Metal `StereogramParams` struct.
    private struct Params {
        var width: Int32
        var height: Int32
        var vwidth: Int32
        var oversam: Int32
        var vmaxsep: Int32
        var s: Int32
        var poffset: Int32
        var yShift: Int32
        var patWidth: Int32
        var patHeight: Int32
        var sourceWidth: Int32
        var sourceHeight: Int32
        var maxdepthF: Float
        var depthRange: Float
        var veyeSepF: Float
        var obsDistF: Float
        var adjMin: Float
        var adjSafeRange: Float
        var adjStart: Float
        var adjEnd: Float
        var tScale: Float
        var tOffsetX: Float
        var tOffsetY: Float
        var invert: Int32
    }

    private init?() {
        guard let dev = MTLCreateSystemDefaultDevice() else { return nil }
        guard let q = dev.makeCommandQueue() else { return nil }

        let library: MTLLibrary
        do {
            library = try Self.loadLibrary(device: dev)
        } catch {
            return nil
        }
        guard let fn = library.makeFunction(name: "stereogram_row") else { return nil }
        guard let pso = try? dev.makeComputePipelineState(function: fn) else { return nil }

        self.device = dev
        self.queue = q
        self.pipeline = pso
    }

    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        let bundle = Bundle(for: MetalStereogramRenderer.self)
        if let url = bundle.url(forResource: "default", withExtension: "metallib"),
           let lib = try? device.makeLibrary(URL: url) {
            return lib
        }
        if let lib = try? device.makeDefaultLibrary(bundle: bundle) {
            return lib
        }
        if let lib = device.makeDefaultLibrary() {
            return lib
        }
        throw NSError(domain: "MetalStereogramRenderer", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "No Metal library found"])
    }

    /// Render a stereogram. Returns RGBA8 pixels of size `width * height * 4`.
    /// `rawDepths` is the source-resolution depth array (sourceWidth × sourceHeight);
    /// the kernel resamples + applies adjustments on the fly.
    func render(
        rawDepths: [Float],
        sourceWidth: Int,
        sourceHeight: Int,
        pattern: [UInt8],
        patWidth: Int,
        patHeight: Int,
        adjMin: Float,
        adjSafeRange: Float,
        adjStart: Float,
        adjEnd: Float,
        transform: DepthTransform,
        params p: StereogramKernelParams
    ) -> [UInt8]? {
        let vCount = p.vwidth * p.height
        let outCount = p.width * p.height

        guard let depthBuf = device.makeBuffer(length: MemoryLayout<Float>.size * rawDepths.count,
                                               options: .storageModeShared) else { return nil }
        rawDepths.withUnsafeBytes { src in
            depthBuf.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        guard let patternBuf = device.makeBuffer(length: pattern.count, options: .storageModeShared) else { return nil }
        pattern.withUnsafeBytes { src in
            patternBuf.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        guard
            let lookL = device.makeBuffer(length: MemoryLayout<Int32>.size * vCount, options: .storageModePrivate),
            let lookR = device.makeBuffer(length: MemoryLayout<Int32>.size * vCount, options: .storageModePrivate),
            let colour = device.makeBuffer(length: 4 * vCount, options: .storageModePrivate),
            let empty = device.makeBuffer(length: vCount, options: .storageModePrivate),
            let outBuf = device.makeBuffer(length: 4 * outCount, options: .storageModeShared)
        else { return nil }

        var params = Params(
            width: Int32(p.width),
            height: Int32(p.height),
            vwidth: Int32(p.vwidth),
            oversam: Int32(p.oversam),
            vmaxsep: Int32(p.vmaxsep),
            s: Int32(p.s),
            poffset: Int32(p.poffset),
            yShift: Int32(p.yShift),
            patWidth: Int32(patWidth),
            patHeight: Int32(patHeight),
            sourceWidth: Int32(sourceWidth),
            sourceHeight: Int32(sourceHeight),
            maxdepthF: p.maxdepthF,
            depthRange: p.depthRange,
            veyeSepF: p.veyeSepF,
            obsDistF: p.obsDistF,
            adjMin: adjMin,
            adjSafeRange: adjSafeRange,
            adjStart: adjStart,
            adjEnd: adjEnd,
            tScale: transform.scale,
            tOffsetX: transform.offsetX,
            tOffsetY: transform.offsetY,
            invert: p.invert ? 1 : 0
        )

        guard let cb = queue.makeCommandBuffer(),
              let enc = cb.makeComputeCommandEncoder() else { return nil }

        enc.setComputePipelineState(pipeline)
        enc.setBuffer(depthBuf,   offset: 0, index: 0)
        enc.setBuffer(patternBuf, offset: 0, index: 1)
        enc.setBuffer(lookL,      offset: 0, index: 2)
        enc.setBuffer(lookR,      offset: 0, index: 3)
        enc.setBuffer(colour,     offset: 0, index: 4)
        enc.setBuffer(empty,      offset: 0, index: 5)
        enc.setBuffer(outBuf,     offset: 0, index: 6)
        enc.setBytes(&params, length: MemoryLayout<Params>.size, index: 7)

        let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, 64)
        let groups = (p.height + threadsPerGroup - 1) / threadsPerGroup
        enc.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                 threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1))
        enc.endEncoding()

        cb.commit()
        cb.waitUntilCompleted()

        if cb.status == .error { return nil }

        var pixels = [UInt8](repeating: 0, count: 4 * outCount)
        pixels.withUnsafeMutableBytes { dst in
            memcpy(dst.baseAddress!, outBuf.contents(), 4 * outCount)
        }
        return pixels
    }
}

struct StereogramKernelParams {
    let width: Int
    let height: Int
    let vwidth: Int
    let oversam: Int
    let vmaxsep: Int
    let s: Int
    let poffset: Int
    let yShift: Int
    let maxdepthF: Float
    let depthRange: Float
    let veyeSepF: Float
    let obsDistF: Float
    let invert: Bool
}
