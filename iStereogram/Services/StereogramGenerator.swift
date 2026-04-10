import UIKit

final class StereogramGenerator {
    /// Generates an autostereogram from a depth map using the Thimbleby algorithm.
    func generate(depthMap: DepthMap, settings: StereogramSettings) -> UIImage {
        let minDimTarget = 960
        let rawWidth = depthMap.width > 0 ? depthMap.width : 1024
        let rawHeight = depthMap.height > 0 ? depthMap.height : 768
        let minDim = min(rawWidth, rawHeight)
        let scale = minDim < minDimTarget ? Int((Float(minDimTarget) / Float(minDim)).rounded(.up)) : 1
        let width = rawWidth * scale
        let height = rawHeight * scale
        let stripWidth = settings.stripWidth
        let amplitude = settings.depthAmplitude

        let depths = depthMap.normalizedDepthValues(width: width, height: height)

        // Prepare pattern data (shared read-only across rows)
        let patternData = preparePattern(settings.pattern, stripWidth: stripWidth)
        let patternWidth = patternData.width
        let patternHeight = patternData.height
        let patternPixels = patternData.pixels

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        DispatchQueue.concurrentPerform(iterations: height) { row in
            // Build link array: links[x] points to the pixel x must match
            var links = [Int](0..<width)

            for x in 0..<width {
                var depth = depths[row * width + x]
                if settings.invert { depth = 1.0 - depth }

                let separation = Int((Float(stripWidth) * (1.0 - amplitude * depth)).rounded())
                let left = x - separation / 2
                let right = left + separation

                if left >= 0 && right < width {
                    var target = left
                    while links[target] != target { target = links[target] }
                    if target != right {
                        links[right] = target
                    }
                }
            }

            // Resolve pixel colors by following links to the pattern strip
            let rowOffset = row * width * 4
            let py = row % patternHeight

            for x in 0..<width {
                var resolvedX = x
                var maxIter = width
                while links[resolvedX] != resolvedX && maxIter > 0 {
                    resolvedX = links[resolvedX]
                    maxIter -= 1
                }
                let px = resolvedX % patternWidth
                let pi = (py * patternWidth + px) * 4
                let oi = rowOffset + x * 4
                pixels[oi]     = patternPixels[pi]
                pixels[oi + 1] = patternPixels[pi + 1]
                pixels[oi + 2] = patternPixels[pi + 2]
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

    private func preparePattern(_ pattern: StereogramPattern, stripWidth: Int) -> PatternData {
        let sourceImage = pattern.loadImage()
        guard let cgImage = sourceImage.cgImage else {
            fatalError("Cannot get CGImage from pattern: \(pattern.displayName)")
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
