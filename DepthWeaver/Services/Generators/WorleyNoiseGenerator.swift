import CoreGraphics
import Foundation

struct WorleyNoiseGenerator: PatternGenerator {
    let config: WorleyConfig

    func generate(size: CGSize) -> PlatformImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return PlatformImage() }

        var rng = SeededRNG(seed: config.seed)
        let cellSize = max(10.0, config.cellSize)

        // Generate seed points on a grid with jitter
        let cellsX = max(1, Int(ceil(Float(width) / cellSize)))
        let cellsY = max(1, Int(ceil(Float(height) / cellSize)))
        let cw = Float(width) / Float(cellsX)
        let ch = Float(height) / Float(cellsY)

        var points: [(Float, Float)] = []
        for cy in 0..<cellsY {
            for cx in 0..<cellsX {
                let px = (Float(cx) + 0.5 + (rng.nextFloat() - 0.5) * 0.8) * cw
                let py = (Float(cy) + 0.5 + (rng.nextFloat() - 0.5) * 0.8) * ch
                points.append((px, py))
            }
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let fw = Float(width)
        let fh = Float(height)

        for y in 0..<height {
            for x in 0..<width {
                let px = Float(x)
                let py = Float(y)

                // Find F1 and F2 distances with toroidal wrapping
                var d1 = Float.greatestFiniteMagnitude
                var d2 = Float.greatestFiniteMagnitude

                for point in points {
                    let d = toroidalDistance(px, py, point.0, point.1, fw, fh)
                    if d < d1 {
                        d2 = d1
                        d1 = d
                    } else if d < d2 {
                        d2 = d
                    }
                }

                let value: Float
                switch config.combineMode {
                case .f1:
                    value = d1 / cellSize
                case .f2:
                    value = d2 / cellSize
                case .f2MinusF1:
                    value = (d2 - d1) / cellSize
                }

                let clamped = max(0, min(1, config.invertLuminance ? 1.0 - value : value))
                let byte = UInt8(clamped * 255)
                let idx = (y * width + x) * 4
                pixels[idx] = byte
                pixels[idx + 1] = byte
                pixels[idx + 2] = byte
                pixels[idx + 3] = 255
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    private func toroidalDistance(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ w: Float, _ h: Float
    ) -> Float {
        var dx = abs(x1 - x2)
        var dy = abs(y1 - y2)
        if dx > w * 0.5 { dx = w - dx }
        if dy > h * 0.5 { dy = h - dy }

        switch config.distanceFunction {
        case .euclidean:
            return sqrt(dx * dx + dy * dy)
        case .manhattan:
            return dx + dy
        case .chebyshev:
            return max(dx, dy)
        }
    }
}
