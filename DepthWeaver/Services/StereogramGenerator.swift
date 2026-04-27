import UIKit

final class StereogramGenerator {
    /// Generates an autostereogram from a depth map.
    /// Implements the algorithm of W.A. Steer (techmind.org), an extension of the
    /// Thimbleby–Inglis–Witten random-dot algorithm with link-based hidden-surface
    /// removal, bitmapped patterns, oversampling, and centre-outwards application.
    func generate(depthMap: DepthMap, settings: StereogramSettings) -> UIImage {
        // Output size: keep input aspect, ensure min dimension >= 960.
        let minDimTarget = 960
        let rawWidth = depthMap.width > 0 ? depthMap.width : 1024
        let rawHeight = depthMap.height > 0 ? depthMap.height : 768
        let minDim = min(rawWidth, rawHeight)
        let scale = minDim < minDimTarget ? Int((Float(minDimTarget) / Float(minDim)).rounded(.up)) : 1
        let width = rawWidth * scale
        let height = rawHeight * scale

        // Geometry constants (PDF). All in pixels.
        let xdpi = max(30, settings.dpi)
        let ydpi = xdpi
        let oversam = max(1, settings.oversampling)
        let obsDist = xdpi * 12
        let eyeSep = (xdpi * 5) / 2          // 2.5 inches
        let veyeSep = eyeSep * oversam

        let depthStrength = max(0.1, settings.depthStrength)
        let sepFactor = min(0.95, max(0.05, settings.sepFactor))

        let maxdepth = max(1, Int((Float(obsDist) * depthStrength).rounded()))
        let mindepthF = (sepFactor * Float(maxdepth) * Float(obsDist)) /
                       ((1.0 - sepFactor) * Float(maxdepth) + Float(obsDist))
        let mindepth = max(0, Int(mindepthF.rounded()))

        let maxsep = max(1, (eyeSep * maxdepth) / (maxdepth + obsDist))
        let vmaxsep = oversam * maxsep
        let yShift = ydpi / 16
        let vwidth = width * oversam

        // Defensive bounds. With reasonable settings vmaxsep is well below vwidth.
        guard vmaxsep > 0, vmaxsep < vwidth else {
            return UIImage()
        }

        let s = vwidth / 2 - vmaxsep / 2
        let poffset = vmaxsep - (s % vmaxsep)

        // Depth values, normalized to [0..1] with 1 = nearest.
        let depths = depthMap.adjustedDepthValues(width: width, height: height)
        let invert = settings.invert

        // Pattern resized so its width equals maxsep (real pixels).
        let pat = preparePattern(settings.patternSource, targetWidth: maxsep)
        let patWidth = pat.width
        let patHeight = pat.height
        let patPixels = pat.pixels

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let depthRange = Float(maxdepth - mindepth)
        let maxdepthF = Float(maxdepth)
        let obsDistF = Float(obsDist)
        let veyeSepF = Float(veyeSep)

        DispatchQueue.concurrentPerform(iterations: height) { y in
            var lookL = [Int](repeating: 0, count: vwidth)
            var lookR = [Int](repeating: 0, count: vwidth)
            var colour = [UInt8](repeating: 0, count: vwidth * 4)

            for x in 0..<vwidth {
                lookL[x] = x
                lookR[x] = x
            }

            // --- 1. Linking pass (TIW + Steer hidden-surface removal) ---
            let depthRowOffset = y * width
            var sep = 0
            for x in 0..<vwidth {
                if x % oversam == 0 {
                    var h = depths[depthRowOffset + x / oversam]
                    if invert { h = 1.0 - h }
                    if h < 0 { h = 0 } else if h > 1 { h = 1 }
                    let featureZ = maxdepthF - h * depthRange
                    sep = Int((veyeSepF * featureZ / (featureZ + obsDistF)).rounded())
                }
                let left = x - sep / 2
                let right = left + sep
                if left < 0 || right >= vwidth { continue }
                var vis = true
                if lookL[right] != right {
                    if lookL[right] < left {
                        let oldLeft = lookL[right]
                        lookR[oldLeft] = oldLeft
                        lookL[right] = right
                    } else {
                        vis = false
                    }
                }
                if lookR[left] != left {
                    if lookR[left] > right {
                        let oldRight = lookR[left]
                        lookL[oldRight] = oldRight
                        lookR[left] = left
                    } else {
                        vis = false
                    }
                }
                if vis {
                    lookL[right] = left
                    lookR[left] = right
                }
            }

            // --- 2. Pattern application: centre to right ---
            var lastlinked = -10
            for x in s..<vwidth {
                let dst = x * 4
                if lookL[x] == x || lookL[x] < s {
                    if lastlinked == x - 1 {
                        let src = (x - 1) * 4
                        colour[dst]     = colour[src]
                        colour[dst + 1] = colour[src + 1]
                        colour[dst + 2] = colour[src + 2]
                    } else {
                        let px = (((x + poffset) % vmaxsep) / oversam) % patWidth
                        let row = (y + ((x - s) / vmaxsep) * yShift) % patHeight
                        let pp = (row * patWidth + px) * 4
                        colour[dst]     = patPixels[pp]
                        colour[dst + 1] = patPixels[pp + 1]
                        colour[dst + 2] = patPixels[pp + 2]
                    }
                } else {
                    let src = lookL[x] * 4
                    colour[dst]     = colour[src]
                    colour[dst + 1] = colour[src + 1]
                    colour[dst + 2] = colour[src + 2]
                    lastlinked = x
                }
                colour[dst + 3] = 255
            }

            // --- 3. Pattern application: centre to left ---
            lastlinked = -10
            if s > 0 {
                var x = s - 1
                while x >= 0 {
                    let dst = x * 4
                    if lookR[x] == x {
                        if lastlinked == x + 1 {
                            let src = (x + 1) * 4
                            colour[dst]     = colour[src]
                            colour[dst + 1] = colour[src + 1]
                            colour[dst + 2] = colour[src + 2]
                        } else {
                            let px = (((x + poffset) % vmaxsep) / oversam) % patWidth
                            let row = (y + ((s - x) / vmaxsep + 1) * yShift) % patHeight
                            let pp = (row * patWidth + px) * 4
                            colour[dst]     = patPixels[pp]
                            colour[dst + 1] = patPixels[pp + 1]
                            colour[dst + 2] = patPixels[pp + 2]
                        }
                    } else {
                        let src = lookR[x] * 4
                        colour[dst]     = colour[src]
                        colour[dst + 1] = colour[src + 1]
                        colour[dst + 2] = colour[src + 2]
                        lastlinked = x
                    }
                    colour[dst + 3] = 255
                    x -= 1
                }
            }

            // --- 4. Downsample virtual pixels into real output pixels ---
            let rowOffset = y * width * 4
            for xr in 0..<width {
                var r = 0, g = 0, b = 0
                let baseV = xr * oversam
                for i in 0..<oversam {
                    let p = (baseV + i) * 4
                    r += Int(colour[p])
                    g += Int(colour[p + 1])
                    b += Int(colour[p + 2])
                }
                let oi = rowOffset + xr * 4
                pixels[oi]     = UInt8(min(255, r / oversam))
                pixels[oi + 1] = UInt8(min(255, g / oversam))
                pixels[oi + 2] = UInt8(min(255, b / oversam))
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

    private func preparePattern(_ source: PatternSource, targetWidth: Int) -> PatternData {
        let safeWidth = max(1, targetWidth)
        let sourceImage = source.generateImage(size: CGSize(width: safeWidth, height: safeWidth))
        guard let cgImage = sourceImage.cgImage else {
            fatalError("Cannot get CGImage from pattern: \(source.displayName)")
        }

        let sourceWidth = cgImage.width
        let sourceHeight = cgImage.height
        let outWidth = safeWidth
        let outHeight = max(1, sourceHeight * outWidth / max(1, sourceWidth))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = outWidth * 4
        var rawPixels = [UInt8](repeating: 0, count: outWidth * outHeight * 4)

        guard let context = CGContext(
            data: &rawPixels,
            width: outWidth,
            height: outHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("Cannot create CGContext for pattern")
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

        return PatternData(pixels: rawPixels, width: outWidth, height: outHeight)
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
