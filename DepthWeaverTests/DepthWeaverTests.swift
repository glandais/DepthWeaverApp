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

        // Per-channel byte difference statistics over RGB (skip alpha).
        var sumAbsDiff: Double = 0
        var maxAbsDiff: Int = 0
        var matchingChannels: Int = 0
        var totalChannels: Int = 0
        for i in stride(from: 0, to: metalPixels.count, by: 4) {
            for c in 0..<3 {
                let d = abs(Int(metalPixels[i + c]) - Int(cpuPixels[i + c]))
                sumAbsDiff += Double(d)
                if d > maxAbsDiff { maxAbsDiff = d }
                if d <= 2 { matchingChannels += 1 }
                totalChannels += 1
            }
        }
        let meanAbsDiff = sumAbsDiff / Double(totalChannels)
        let matchRatio = Double(matchingChannels) / Double(totalChannels)

        print("Metal vs CPU — meanAbsDiff=\(meanAbsDiff), maxAbsDiff=\(maxAbsDiff), matchRatio(±2)=\(matchRatio)")

        // Both paths use fp32 with the same OKLab math; small rounding differences are
        // expected at gap-fill boundaries. Tight but not pixel-identical thresholds.
        #expect(meanAbsDiff < 1.0,
                "average per-channel byte difference too large: \(meanAbsDiff)")
        #expect(matchRatio > 0.99,
                "fraction of channels matching within ±2 too low: \(matchRatio)")
        #expect(maxAbsDiff <= 16,
                "max per-channel byte difference too large: \(maxAbsDiff)")
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
