import UIKit

final class StereogramGenerator {
    /// Generates an autostereogram using stripe-based displacement.
    /// Ported from stereogram-webgl (computeTileUv / sampleHeightmap shaders).
    func generate(depthMap: DepthMap, settings: StereogramSettings) -> UIImage {
        let minDimTarget = 960
        let rawWidth = depthMap.width > 0 ? depthMap.width : 1024
        let rawHeight = depthMap.height > 0 ? depthMap.height : 768
        let minDim = min(rawWidth, rawHeight)
        let scale = minDim < minDimTarget ? Int((Float(minDimTarget) / Float(minDim)).rounded(.up)) : 1
        let width = rawWidth * scale
        let height = rawHeight * scale

        let stripesCount = settings.stripesCount
        let depthFactor = settings.depthFactor
        let invertDepth = settings.invert
        let mainStripeIdx = settings.mainStripePosition == .left ? 0 : stripesCount / 2
        let loopSize = 2 * stripesCount

        let depths = depthMap.adjustedDepthValues(width: width, height: height)

        let stripeWidthPx = max(1, width / (stripesCount + 1))
        let patternData = preparePattern(settings.patternSource, stripWidth: stripeWidthPx)
        let patternW = patternData.width
        let patternH = patternData.height
        let patternPx = patternData.pixels

        // Tile height in normalized output coords (preserves pattern aspect ratio)
        let tileWidthPx = Float(width) / Float(stripesCount + 1)
        let tileHeightPx = tileWidthPx * Float(patternH) / Float(patternW)
        let tileHeight = tileHeightPx / Float(height)

        // Heightmap scaling: aspect-fit depth map into the "useful" portion of the canvas.
        // The useful portion is stripesCount/(stripesCount+1) of the total width.
        let usefulProportion = Float(stripesCount) / Float(stripesCount + 1)
        let canvasAR = Float(width) / Float(height) * usefulProportion
        let heightmapAR = Float(width) / Float(height)
        let hmScaleX: Float
        let hmScaleY: Float
        if canvasAR > heightmapAR {
            hmScaleX = canvasAR / heightmapAR
            hmScaleY = 1.0
        } else {
            hmScaleX = 1.0
            hmScaleY = heightmapAR / canvasAR
        }

        let mainStripe = Float(mainStripeIdx)
        let stripesCountF = Float(stripesCount)
        let stripesCountP1F = Float(stripesCount + 1)
        let widthF = Float(width)
        let heightF = Float(height)
        let widthM1F = Float(width - 1)
        let heightM1F = Float(height - 1)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        DispatchQueue.concurrentPerform(iterations: height) { row in
            let rowOffset = row * width * 4
            let posY = (Float(row) + 0.5) / heightF

            // Bilinear depth sampling with heightmap scaling, inversion, and depth factor.
            // Equivalent to sampleHeightmap() in _heightmap.frag.
            @inline(__always)
            func sampleHM(_ nx: Float, _ ny: Float) -> Float {
                let sx = 0.5 + (nx - 0.5) * hmScaleX
                let sy = 0.5 + (ny - 0.5) * hmScaleY
                guard sx >= 0, sx <= 1, sy >= 0, sy <= 1 else { return 0 }

                let fx = sx * widthM1F
                let fy = sy * heightM1F
                let x0 = min(Int(fx), width - 1)
                let y0 = min(Int(fy), height - 1)
                let x1 = min(x0 + 1, width - 1)
                let y1 = min(y0 + 1, height - 1)
                let dx = fx - Float(x0)
                let dy = fy - Float(y0)

                let v = depths[y0 * width + x0] * (1 - dx) * (1 - dy)
                    + depths[y0 * width + x1] * dx * (1 - dy)
                    + depths[y1 * width + x0] * (1 - dx) * dy
                    + depths[y1 * width + x1] * dx * dy

                let value = invertDepth ? 1.0 - v : v
                return depthFactor * value
            }

            // Main stripe bounds for this row (constant per row).
            // The main stripe width varies with the depth at its center.
            let mainSampleX = (mainStripe + 0.5) / stripesCountP1F
            let mainDepth = sampleHM(mainSampleX, posY)
            let mainStripeW = 1.0 - mainDepth * 0.45
            let mainLeft = mainStripe + 0.5 * (1.0 - mainStripeW)
            let mainRight = mainStripe + 1.0 - 0.5 * (1.0 - mainStripeW)

            for col in 0..<width {
                // Map pixel to stripe-space [0, stripesCount+1]
                var posX = (Float(col) + 0.5) / widthF * stripesCountP1F

                // Iteratively displace towards the main stripe.
                // Each step shifts by one stripe width adjusted by depth.
                for _ in 0..<loopSize {
                    if posX < mainLeft {
                        let prevX = (posX - 0.25) / stripesCountF
                        posX += 1.0 - sampleHM(prevX, posY) * 0.45
                    } else if posX >= mainRight {
                        let prevX = (posX - 1.0) / stripesCountF
                        posX -= 1.0 - sampleHM(prevX, posY) * 0.45
                    } else {
                        break
                    }
                }

                // Map converged position to tile UV
                let tileU = (posX - mainLeft) / mainStripeW
                var tileV = posY / tileHeight
                tileV = tileV - floor(tileV) // fract

                // Sample pattern with wrapping
                var pxI = Int(tileU * Float(patternW))
                pxI = ((pxI % patternW) + patternW) % patternW
                var pyI = Int(tileV * Float(patternH))
                pyI = ((pyI % patternH) + patternH) % patternH

                let pi = (pyI * patternW + pxI) * 4
                let oi = rowOffset + col * 4
                pixels[oi]     = patternPx[pi]
                pixels[oi + 1] = patternPx[pi + 1]
                pixels[oi + 2] = patternPx[pi + 2]
                pixels[oi + 3] = 255
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    // MARK: - Pattern Preparation

    private struct PatternData {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private func preparePattern(_ source: PatternSource, stripWidth: Int) -> PatternData {
        let sourceImage = source.generateImage(size: CGSize(width: stripWidth, height: stripWidth))
        guard let cgImage = sourceImage.cgImage else {
            fatalError("Cannot get CGImage from pattern: \(source.displayName)")
        }

        let sourceHeight = cgImage.height
        let sourceWidth = cgImage.width
        let targetWidth = stripWidth
        let targetHeight = sourceHeight * targetWidth / sourceWidth

        // Render pattern scaled to stripWidth
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = targetWidth * 4
        var rawPixels = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)

        guard let context = CGContext(
            data: &rawPixels,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Cannot create CGContext for pattern")
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        return PatternData(pixels: rawPixels, width: targetWidth, height: targetHeight)
    }

    // MARK: - Image Creation

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
