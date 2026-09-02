import CoreGraphics
import Foundation
import Testing

@Suite("StereogramGenerator")
struct StereogramGeneratorTests {

    @Test("generates a valid stereogram from the dog height map with default settings")
    func generatesDogStereogramWithDefaults() throws {
        let depthMap = DepthMapPreset.dog.toDepthMap()
        let settings = StereogramSettings()

        let start = Date()
        let image = StereogramGenerator().generate(depthMap: depthMap, settings: settings)
        let elapsed = Date().timeIntervalSince(start)
        let cgImage = try #require(image.cgImage, "generator returned an empty PlatformImage")
        
        print("Rendering took \(elapsed)s")
        #expect(elapsed < 2.0, "rendering took \(elapsed)s, expected < 2s")

        // dog.png is 500×500. DepthMap(image:) keeps it at 500×500 (≤ 1024 max side).
        // StereogramGenerator upscales by ⌈960/500⌉ = 2, so output is 1000×1000.
        #expect(cgImage.width == 1000)
        #expect(cgImage.height == 1000)

        let pixels = try #require(samplePixels(cgImage: cgImage), "failed to read pixels")
        #expect(pixels.count == cgImage.width * cgImage.height * 4)

        // The result must contain real pattern content, not a uniform fill / black image.
        // Sample R-channel statistics: mean should be mid-range, std-dev meaningfully > 0.
        var sum: Double = 0
        var sumSq: Double = 0
        let sampleCount = cgImage.width * cgImage.height
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = Double(pixels[i])
            sum += v
            sumSq += v * v
        }
        let mean = sum / Double(sampleCount)
        let variance = sumSq / Double(sampleCount) - mean * mean
        let stdDev = sqrt(max(0, variance))

        #expect(mean > 20 && mean < 235, "image is not uniformly black/white (mean=\(mean))")
        #expect(stdDev > 30, "image has visible pattern variation (stdDev=\(stdDev))")
    }

    @Test("Metal and CPU stereograms are nearly identical for the dog height map")
    func metalAndCpuOutputsAreClose() throws {
        try #require(MetalStereogramRenderer.shared != nil,
                     "Metal renderer unavailable on this host — skipping comparison")

        let depthMap = DepthMapPreset.dog.toDepthMap()
        let settings = StereogramSettings()
        let generator = StereogramGenerator()

        let metalImage = generator.generate(depthMap: depthMap, settings: settings, useMetal: true)
        let cpuImage = generator.generate(depthMap: depthMap, settings: settings, useMetal: false)

        let metalCG = try #require(metalImage.cgImage, "Metal path returned an empty image")
        let cpuCG = try #require(cpuImage.cgImage, "CPU path returned an empty image")

        #expect(metalCG.width == cpuCG.width)
        #expect(metalCG.height == cpuCG.height)

        let metalPixels = try #require(samplePixels(cgImage: metalCG), "failed to read Metal pixels")
        let cpuPixels = try #require(samplePixels(cgImage: cpuCG), "failed to read CPU pixels")
        #expect(metalPixels.count == cpuPixels.count)

        let diff = channelDifference(metalPixels, cpuPixels)
        print("Metal vs CPU — meanAbsDiff=\(diff.mean), maxAbsDiff=\(diff.max), matchRatio(±2)=\(diff.matchRatio)")
        expectPathsAgree(diff)
    }

    @Test("the live framing resamples identically on the Metal and CPU paths")
    func transformedMetalAndCpuOutputsAreClose() throws {
        try #require(MetalStereogramRenderer.shared != nil,
                     "Metal renderer unavailable on this host — skipping comparison")

        // A framing a live-mode gesture could plausibly land on: zoomed in on
        // the dog and dragged off-centre on both axes.
        var depthMap = DepthMapPreset.dog.toDepthMap()
        depthMap.transform.zoom(by: 2.5)
        depthMap.transform.pan(dx: 0.18, dy: -0.11)
        #expect(depthMap.transform.offsetX != 0)
        #expect(depthMap.transform.offsetY != 0)

        let settings = StereogramSettings()
        let generator = StereogramGenerator()
        let metalCG = try #require(
            generator.generate(depthMap: depthMap, settings: settings, useMetal: true).cgImage,
            "Metal path returned an empty image"
        )
        let cpuCG = try #require(
            generator.generate(depthMap: depthMap, settings: settings, useMetal: false).cgImage,
            "CPU path returned an empty image"
        )

        let metalPixels = try #require(samplePixels(cgImage: metalCG), "failed to read Metal pixels")
        let cpuPixels = try #require(samplePixels(cgImage: cpuCG), "failed to read CPU pixels")
        #expect(metalPixels.count == cpuPixels.count)

        let diff = channelDifference(metalPixels, cpuPixels)
        print("Transformed Metal vs CPU — meanAbsDiff=\(diff.mean), maxAbsDiff=\(diff.max), matchRatio(±2)=\(diff.matchRatio)")
        expectPathsAgree(diff)
    }

    @Test("zooming the depth map changes the rendered stereogram")
    func transformChangesTheRender() throws {
        let settings = StereogramSettings()
        let generator = StereogramGenerator()

        let base = DepthMapPreset.dog.toDepthMap()
        var zoomed = base
        zoomed.transform.zoom(by: 3)

        let baseCG = try #require(generator.generate(depthMap: base, settings: settings).cgImage)
        let zoomedCG = try #require(generator.generate(depthMap: zoomed, settings: settings).cgImage)

        // Same map, same settings: only the framing moved, so the output keeps
        // its size and the pattern has to be laid out differently.
        #expect(baseCG.width == zoomedCG.width)
        #expect(baseCG.height == zoomedCG.height)

        let basePixels = try #require(samplePixels(cgImage: baseCG))
        let zoomedPixels = try #require(samplePixels(cgImage: zoomedCG))
        let diff = channelDifference(basePixels, zoomedPixels)
        #expect(diff.matchRatio < 0.9,
                "zoomed render is suspiciously close to the unzoomed one (matchRatio=\(diff.matchRatio))")
    }

    // MARK: - Helpers

    private func expectPathsAgree(_ diff: (mean: Double, max: Int, matchRatio: Double)) {
        // Both paths use fp32 with the same OKLab math; small rounding differences are
        // expected at gap-fill boundaries. Tight but not pixel-identical thresholds.
        #expect(diff.mean < 1.0,
                "average per-channel byte difference too large: \(diff.mean)")
        #expect(diff.matchRatio > 0.99,
                "fraction of channels matching within ±2 too low: \(diff.matchRatio)")
        #expect(diff.max <= 16,
                "max per-channel byte difference too large: \(diff.max)")
    }

    /// Per-channel byte difference statistics over RGB (skip alpha).
    private func channelDifference(
        _ lhs: [UInt8],
        _ rhs: [UInt8]
    ) -> (mean: Double, max: Int, matchRatio: Double) {
        var sumAbsDiff: Double = 0
        var maxAbsDiff = 0
        var matchingChannels = 0
        var totalChannels = 0
        for i in stride(from: 0, to: Swift.min(lhs.count, rhs.count), by: 4) {
            for c in 0..<3 {
                let d = abs(Int(lhs[i + c]) - Int(rhs[i + c]))
                sumAbsDiff += Double(d)
                if d > maxAbsDiff { maxAbsDiff = d }
                if d <= 2 { matchingChannels += 1 }
                totalChannels += 1
            }
        }
        guard totalChannels > 0 else { return (0, 0, 1) }
        return (
            sumAbsDiff / Double(totalChannels),
            maxAbsDiff,
            Double(matchingChannels) / Double(totalChannels)
        )
    }

    private func samplePixels(cgImage: CGImage) -> [UInt8]? {
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }
}

@Suite("DepthTransform")
struct DepthTransformTests {

    @Test("the identity transform frames the whole map")
    func identityFramesEverything() {
        let transform = DepthTransform.identity
        #expect(transform.isIdentity)
        #expect(transform.sourceU(0) == 0)
        #expect(transform.sourceU(1) == 1)
        #expect(abs(transform.sourceV(0.5) - 0.5) < 1e-6)
    }

    @Test("panning cannot push the window off the map")
    func panIsClampedToTheMap() {
        var transform = DepthTransform()
        transform.zoom(by: 2)
        // Far past the edge on both axes.
        transform.pan(dx: 10, dy: -10)

        #expect(abs(transform.offsetX - 0.25) < 1e-6)
        #expect(abs(transform.offsetY + 0.25) < 1e-6)
        // The visible window sits flush against the left / bottom edge.
        #expect(transform.sourceU(0) == 0)
        #expect(abs(transform.sourceU(1) - 0.5) < 1e-6)
        #expect(abs(transform.sourceV(0) - 0.5) < 1e-6)
        #expect(transform.sourceV(1) == 1)
    }

    @Test("zoom stays in range and re-clamps the offsets on the way out")
    func zoomIsClampedAndResetsPan() {
        var transform = DepthTransform()
        transform.zoom(by: 1000)
        #expect(transform.scale == DepthTransform.maxScale)

        transform.pan(dx: 1, dy: 1)
        #expect(transform.offsetX > 0)

        transform.zoom(by: 0.0001)
        #expect(transform.scale == DepthTransform.minScale)
        // Nothing to pan towards once the whole map is framed again.
        #expect(transform.offsetX == 0)
        #expect(transform.offsetY == 0)
        #expect(transform.isIdentity)
    }
}
