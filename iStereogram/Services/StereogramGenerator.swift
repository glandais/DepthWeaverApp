import UIKit

final class StereogramGenerator {
    /// Generates an autostereogram from a depth map using the Thimbleby algorithm
    /// with center-outward processing and union-find constraint propagation.
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
            // Build union-find constraint array
            var same = [Int](0..<width)
            let mid = width / 2

            // Process from center to right
            for x in mid..<width {
                processPixel(x: x, y: row, width: width, depths: depths,
                             invert: settings.invert, stripWidth: stripWidth,
                             amplitude: amplitude, same: &same)
            }
            // Process from center to left
            for x in stride(from: mid - 1, through: 0, by: -1) {
                processPixel(x: x, y: row, width: width, depths: depths,
                             invert: settings.invert, stripWidth: stripWidth,
                             amplitude: amplitude, same: &same)
            }

            // Assign colors from center outward
            let rowOffset = row * width * 4
            let py = row % patternHeight

            for x in mid..<width {
                assignPixelColor(x: x, row: row, rowOffset: rowOffset, width: width,
                                 patternWidth: patternWidth, py: py,
                                 same: &same, patternPixels: patternPixels, pixels: &pixels)
            }
            for x in stride(from: mid - 1, through: 0, by: -1) {
                assignPixelColor(x: x, row: row, rowOffset: rowOffset, width: width,
                                 patternWidth: patternWidth, py: py,
                                 same: &same, patternPixels: patternPixels, pixels: &pixels)
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    // MARK: - Pixel Processing

    private func processPixel(x: Int, y: Int, width: Int, depths: [Float],
                               invert: Bool, stripWidth: Int, amplitude: Float,
                               same: inout [Int]) {
        var depth = depths[y * width + x]
        if invert { depth = 1.0 - depth }

        let separation = Int((Float(stripWidth) * (1.0 - amplitude * depth)).rounded())
        let left = x - separation / 2
        let right = left + separation

        guard left >= 0 && right < width else { return }

        // Union-find: follow chains to roots
        var l = left
        while same[l] != l { l = same[l] }
        var r = right
        while same[r] != r { r = same[r] }

        if l != r {
            if l < r { same[r] = l }
            else { same[l] = r }
        }
    }

    private func assignPixelColor(x: Int, row: Int, rowOffset: Int, width: Int,
                                   patternWidth: Int, py: Int,
                                   same: inout [Int], patternPixels: [UInt8],
                                   pixels: inout [UInt8]) {
        // Path compression to find root
        var root = x
        while same[root] != root { root = same[root] }
        var curr = x
        while same[curr] != root {
            let next = same[curr]
            same[curr] = root
            curr = next
        }

        let px = ((root % patternWidth) + patternWidth) % patternWidth
        let pi = (py * patternWidth + px) * 4
        let oi = rowOffset + x * 4
        pixels[oi]     = patternPixels[pi]
        pixels[oi + 1] = patternPixels[pi + 1]
        pixels[oi + 2] = patternPixels[pi + 2]
        pixels[oi + 3] = 255
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
