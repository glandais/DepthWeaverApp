import UIKit

final class StereogramGenerator {
    /// Generates an autostereogram from a depth map using the Thimbleby-Inglis-Witten algorithm.
    func generate(depthMap: DepthMap, settings: StereogramSettings) -> UIImage {
        let minDimTarget = 960
        let rawWidth = depthMap.width > 0 ? depthMap.width : 1024
        let rawHeight = depthMap.height > 0 ? depthMap.height : 768
        let minDim = min(rawWidth, rawHeight)
        let scale = minDim < minDimTarget ? Int((Float(minDimTarget) / Float(minDim)).rounded(.up)) : 1
        let width = rawWidth * scale
        let height = rawHeight * scale
        let stripWidth = settings.stripWidth
        let eyeSep = settings.eyeSeparation

        let depths = depthMap.normalizedDepthValues(width: width, height: height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        DispatchQueue.concurrentPerform(iterations: height) { row in
            // Seeded RNG per row for reproducibility
            var rng = SplitMix64(seed: UInt64(row) &* 0x9E3779B97F4A7C15)

            // Generate random noise strip for this row
            var strip = [UInt8](repeating: 0, count: stripWidth * 4)
            for i in stride(from: 0, to: strip.count, by: 4) {
                strip[i]     = UInt8(rng.next() & 0xFF) // R
                strip[i + 1] = UInt8(rng.next() & 0xFF) // G
                strip[i + 2] = UInt8(rng.next() & 0xFF) // B
                strip[i + 3] = 255                       // A
            }

            // Build link buffer
            var links = Array(0..<width)
            for x in 0..<width {
                var depth = depths[row * width + x]
                if settings.invert { depth = 1.0 - depth }

                let separation = stripWidth - Int(depth * Float(eyeSep))
                let left = x - separation / 2
                let right = left + separation

                if left >= 0 && right >= 0 && right < width {
                    // Follow existing link chain from left
                    var target = left
                    while links[target] != target && links[target] >= 0 {
                        target = links[target]
                    }
                    if target != right {
                        links[right] = target
                    }
                }
            }

            // Resolve pixel colors by following links to the strip
            let rowOffset = row * width * 4
            for x in 0..<width {
                var resolvedX = x
                var maxIterations = width
                while links[resolvedX] != resolvedX && maxIterations > 0 {
                    resolvedX = links[resolvedX]
                    maxIterations -= 1
                }
                let stripX = resolvedX % stripWidth
                pixels[rowOffset + x * 4]     = strip[stripX * 4]
                pixels[rowOffset + x * 4 + 1] = strip[stripX * 4 + 1]
                pixels[rowOffset + x * 4 + 2] = strip[stripX * 4 + 2]
                pixels[rowOffset + x * 4 + 3] = 255
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    private func createImage(from pixels: [UInt8], width: Int, height: Int) -> UIImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let data = Data(pixels)

        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Simple fast PRNG for reproducible noise.
struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
