import UIKit

struct VoronoiGenerator: PatternGenerator {
    let config: VoronoiConfig

    func generate(size: CGSize) -> UIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return UIImage() }

        var rng = SeededRNG(seed: config.seed)
        let cellCount = max(2, config.cellCount)

        // Generate cell centers with jitter
        let gridSize = Int(ceil(sqrt(Float(cellCount))))
        let cellW = Float(width) / Float(gridSize)
        let cellH = Float(height) / Float(gridSize)

        struct CellPoint {
            let x: Float
            let y: Float
            let color: (UInt8, UInt8, UInt8)
        }

        var cells: [CellPoint] = []
        for cy in 0..<gridSize {
            for cx in 0..<gridSize {
                guard cells.count < cellCount else { break }
                let jitterAmount = config.jitter
                let px = (Float(cx) + 0.5 + (rng.nextFloat() - 0.5) * jitterAmount) * cellW
                let py = (Float(cy) + 0.5 + (rng.nextFloat() - 0.5) * jitterAmount) * cellH
                let color = generateColor(index: cells.count, rng: &rng)
                cells.append(CellPoint(x: px, y: py, color: color))
            }
        }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let fw = Float(width)
        let fh = Float(height)
        let edgeThreshold = config.edgeWidth

        for y in 0..<height {
            for x in 0..<width {
                let px = Float(x)
                let py = Float(y)

                // Find nearest and second-nearest with toroidal wrapping
                var d1 = Float.greatestFiniteMagnitude
                var d2 = Float.greatestFiniteMagnitude
                var nearestIdx = 0

                for (i, cell) in cells.enumerated() {
                    let d = toroidalDistEuclidean(px, py, cell.x, cell.y, fw, fh)
                    if d < d1 {
                        d2 = d1
                        d1 = d
                        nearestIdx = i
                    } else if d < d2 {
                        d2 = d
                    }
                }

                let idx = (y * width + x) * 4

                // Edge detection
                if edgeThreshold > 0 && (d2 - d1) < edgeThreshold {
                    pixels[idx] = 0
                    pixels[idx + 1] = 0
                    pixels[idx + 2] = 0
                } else {
                    let c = cells[nearestIdx].color
                    pixels[idx] = c.0
                    pixels[idx + 1] = c.1
                    pixels[idx + 2] = c.2
                }
                pixels[idx + 3] = 255
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    private func generateColor(index: Int, rng: inout SeededRNG) -> (UInt8, UInt8, UInt8) {
        switch config.colorScheme {
        case .pastel:
            let h = rng.nextFloat()
            let (r, g, b) = hsbToRGB(h: h, s: 0.3, b: 0.95)
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))

        case .vivid:
            let h = rng.nextFloat()
            let (r, g, b) = hsbToRGB(h: h, s: 0.9, b: 0.9)
            return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))

        case .monochrome:
            let v = UInt8(100 + rng.nextFloat() * 155)
            return (v, v, v)

        case .random:
            return (
                UInt8(rng.nextFloat() * 255),
                UInt8(rng.nextFloat() * 255),
                UInt8(rng.nextFloat() * 255)
            )
        }
    }

    private func toroidalDistEuclidean(
        _ x1: Float, _ y1: Float,
        _ x2: Float, _ y2: Float,
        _ w: Float, _ h: Float
    ) -> Float {
        var dx = abs(x1 - x2)
        var dy = abs(y1 - y2)
        if dx > w * 0.5 { dx = w - dx }
        if dy > h * 0.5 { dy = h - dy }
        return sqrt(dx * dx + dy * dy)
    }
}
