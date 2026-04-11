import UIKit

struct StarsGenerator: PatternGenerator {
    let config: StarsConfig

    func generate(size: CGSize) -> UIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return UIImage() }

        var rng = SeededRNG(seed: config.seed)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        // Fill background
        let bgR = UInt8(config.backgroundColor.red * 255)
        let bgG = UInt8(config.backgroundColor.green * 255)
        let bgB = UInt8(config.backgroundColor.blue * 255)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = bgR
            pixels[i + 1] = bgG
            pixels[i + 2] = bgB
            pixels[i + 3] = 255
        }

        // Place stars
        for _ in 0..<config.starCount {
            let cx = Int(rng.nextFloat() * Float(width))
            let cy = Int(rng.nextFloat() * Float(height))
            let brightness = UInt8(150 + rng.nextFloat() * 105)
            let r = Int(rng.nextFloat() * Float(config.maxRadius + 1))

            // Draw circular star with wrapping for seamless tiling
            for dy in -r...r {
                for dx in -r...r {
                    if dx * dx + dy * dy <= r * r {
                        let px = (cx + dx + width) % width
                        let py = (cy + dy + height) % height
                        let idx = (py * width + px) * 4
                        pixels[idx] = brightness
                        pixels[idx + 1] = brightness
                        pixels[idx + 2] = brightness
                        pixels[idx + 3] = 255
                    }
                }
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }
}
