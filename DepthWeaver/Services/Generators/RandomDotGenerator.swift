import CoreGraphics
import Foundation

struct RandomDotGenerator: PatternGenerator {
    let config: RandomDotConfig

    func generate(size: CGSize) -> PlatformImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return PlatformImage() }

        var rng = SeededRNG(seed: config.seed)
        let dotSize = max(1, config.dotSize)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        // Fill background with white
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = 255
            pixels[i + 1] = 255
            pixels[i + 2] = 255
            pixels[i + 3] = 255
        }

        // Place dots at given density
        let totalCells = (width / dotSize) * (height / dotSize)
        let dotCount = Int(Float(totalCells) * config.density)

        for _ in 0..<dotCount {
            let cx = Int(rng.nextFloat() * Float(width))
            let cy = Int(rng.nextFloat() * Float(height))

            let (r, g, b) = dotColor(rng: &rng)

            // Stamp dot with wrapping for seamless tiling
            for dy in 0..<dotSize {
                for dx in 0..<dotSize {
                    let px = (cx + dx) % width
                    let py = (cy + dy) % height
                    let idx = (py * width + px) * 4
                    pixels[idx] = r
                    pixels[idx + 1] = g
                    pixels[idx + 2] = b
                    pixels[idx + 3] = 255
                }
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    private func dotColor(rng: inout SeededRNG) -> (UInt8, UInt8, UInt8) {
        switch config.colorMode {
        case .blackAndWhite:
            let v: UInt8 = rng.nextFloat() > 0.5 ? 0 : 255
            return (v, v, v)
        case .grayscale:
            let v = UInt8(rng.nextFloat() * 255)
            return (v, v, v)
        case .color:
            return (
                UInt8(rng.nextFloat() * 255),
                UInt8(rng.nextFloat() * 255),
                UInt8(rng.nextFloat() * 255)
            )
        }
    }
}

// MARK: - Seeded RNG (shared across generators)

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x853C49E6748FEA9B : seed
    }

    mutating func next() -> UInt64 {
        // xorshift64*
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }

    mutating func nextFloat() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

// MARK: - Shared Image Creation

func createImage(from pixels: [UInt8], width: Int, height: Int) -> PlatformImage {
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
        return PlatformImage()
    }
    return PlatformImage(cgImage: cgImage)
}
