import Accelerate
import CoreGraphics
import Foundation

struct ReactionDiffusionGenerator: PatternGenerator {
    let config: ReactionDiffusionConfig

    func generate(size: CGSize) -> PlatformImage {
        // Always simulate at a fixed resolution for performance, then scale
        let simSize = min(128, Int(min(size.width, size.height)))
        let width = simSize
        let height = simSize

        var rng = SeededRNG(seed: config.seed)

        // Initialize concentrations: U = 1 everywhere, V = 0 with dense random seeds
        var u = [Float](repeating: 1.0, count: width * height)
        var v = [Float](repeating: 0.0, count: width * height)

        // Seed V densely across the grid so the pattern fills the entire tile.
        // Use a grid of seed patches with random jitter for even coverage.
        let gridStep = 8  // one seed patch every ~8 pixels
        let seedRadius = 2
        for gy in stride(from: 0, to: height, by: gridStep) {
            for gx in stride(from: 0, to: width, by: gridStep) {
                let cx = (gx + Int(rng.nextFloat() * Float(gridStep))) % width
                let cy = (gy + Int(rng.nextFloat() * Float(gridStep))) % height
                for dy in -seedRadius...seedRadius {
                    for dx in -seedRadius...seedRadius {
                        if dx * dx + dy * dy <= seedRadius * seedRadius {
                            let px = (cx + dx + width) % width
                            let py = (cy + dy + height) % height
                            let idx = py * width + px
                            u[idx] = 0.5
                            v[idx] = 0.25
                        }
                    }
                }
            }
        }

        // Gray-Scott parameters
        let F = config.feedRate
        let k = config.killRate
        let Du: Float = 0.16
        let Dv: Float = 0.08
        let dt: Float = 1.0

        var newU = [Float](repeating: 0, count: width * height)
        var newV = [Float](repeating: 0, count: width * height)

        // Run simulation with periodic boundary conditions
        for _ in 0..<config.iterations {
            // Compute Laplacian and reaction in one pass
            for y in 0..<height {
                let ym = (y - 1 + height) % height
                let yp = (y + 1) % height

                for x in 0..<width {
                    let xm = (x - 1 + width) % width
                    let xp = (x + 1) % width

                    let idx = y * width + x
                    let uVal = u[idx]
                    let vVal = v[idx]

                    // 5-point Laplacian with periodic boundaries
                    let lapU = u[ym * width + x] + u[yp * width + x]
                        + u[y * width + xm] + u[y * width + xp]
                        - 4.0 * uVal
                    let lapV = v[ym * width + x] + v[yp * width + x]
                        + v[y * width + xm] + v[y * width + xp]
                        - 4.0 * vVal

                    let uvv = uVal * vVal * vVal

                    newU[idx] = uVal + dt * (Du * lapU - uvv + F * (1.0 - uVal))
                    newV[idx] = vVal + dt * (Dv * lapV + uvv - (F + k) * vVal)
                }
            }

            swap(&u, &newU)
            swap(&v, &newV)
        }

        // Map V concentration to colors
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude
        vDSP_minv(v, 1, &minV, vDSP_Length(v.count))
        vDSP_maxv(v, 1, &maxV, vDSP_Length(v.count))

        let range = maxV - minV
        let invRange = range > 0 ? 1.0 / range : 1.0

        let cA = config.colorA
        let cB = config.colorB

        var pixels = [UInt8](repeating: 255, count: width * height * 4)

        for i in 0..<(width * height) {
            let t = (v[i] - minV) * invRange
            let r = cA.red + (cB.red - cA.red) * t
            let g = cA.green + (cB.green - cA.green) * t
            let b = cA.blue + (cB.blue - cA.blue) * t

            let idx = i * 4
            pixels[idx] = UInt8(clamping: Int(r * 255))
            pixels[idx + 1] = UInt8(clamping: Int(g * 255))
            pixels[idx + 2] = UInt8(clamping: Int(b * 255))
            pixels[idx + 3] = 255
        }

        let simImage = createImage(from: pixels, width: width, height: height)

        // Scale up to requested size if needed
        let targetW = Int(size.width)
        let targetH = Int(size.height)
        if targetW > width || targetH > height {
            return scaleImage(simImage, to: CGSize(width: targetW, height: targetH))
        }
        return simImage
    }

    private func scaleImage(_ image: PlatformImage, to size: CGSize) -> PlatformImage {
        let w = max(1, Int(size.width))
        let h = max(1, Int(size.height))
        guard let cg = image.cgImage else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: w, height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return image }
        return PlatformImage(cgImage: scaled)
    }
}
