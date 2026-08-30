import CoreGraphics
import Foundation

final class StereogramGenerator {
    /// Generates an autostereogram from a depth map.
    /// Implements the algorithm of W.A. Steer (techmind.org), an extension of the
    /// Thimbleby–Inglis–Witten random-dot algorithm with link-based hidden-surface
    /// removal, bitmapped patterns, oversampling, and centre-outwards application.
    func generate(
        depthMap: DepthMap,
        settings: StereogramSettings,
        useMetal: Bool = true,
        quality: StereogramQuality = .full
    ) -> PlatformImage {
        let (width, height) = Self.outputSize(for: depthMap, quality: quality)

        // Geometry constants (PDF). All in pixels.
        let geometry = Geometry(dpi: settings.dpi, depthStrength: settings.depthStrength)
        let xdpi = geometry.dpi
        let ydpi = xdpi
        let oversam = max(1, settings.oversampling)
        let obsDist = geometry.obsDist
        let eyeSep = geometry.eyeSep
        let veyeSep = eyeSep * oversam

        let sepFactor = min(0.95, max(0.05, settings.sepFactor))

        let maxdepth = geometry.maxdepth
        let mindepthF = (sepFactor * Float(maxdepth) * Float(obsDist)) /
                       ((1.0 - sepFactor) * Float(maxdepth) + Float(obsDist))
        let mindepth = max(0, Int(mindepthF.rounded()))

        let maxsep = geometry.maxsep
        let vmaxsep = oversam * maxsep
        let yShift = ydpi / 16
        let vwidth = width * oversam

        // Defensive bounds. With reasonable settings vmaxsep is well below vwidth.
        guard vmaxsep > 0, vmaxsep < vwidth else {
            return PlatformImage()
        }

        let s = vwidth / 2 - vmaxsep / 2
        let poffset = vmaxsep - (s % vmaxsep)

        let invert = settings.invert

        // Pattern resized so its width equals maxsep (real pixels).
        let pat = preparePattern(settings.patternSource, targetWidth: maxsep)
        let patWidth = pat.width
        let patHeight = pat.height
        let patPixels = pat.pixels

        let depthRange = Float(maxdepth - mindepth)
        let maxdepthF = Float(maxdepth)
        let obsDistF = Float(obsDist)
        let veyeSepF = Float(veyeSep)

        // GPU path: full algorithm runs as a Metal compute kernel.
        if useMetal, let gpu = MetalStereogramRenderer.shared {
            let adjMin = depthMap.adjustment.min
            let adjRange = depthMap.adjustment.max - depthMap.adjustment.min
            let adjSafeRange = adjRange > 0 ? adjRange : 1.0
            let adjStart = 1.0 - depthMap.adjustment.start
            let adjEnd = 1.0 - depthMap.adjustment.end

            if let outPixels = gpu.render(
                rawDepths: depthMap.workingDepth,
                sourceWidth: depthMap.sourceWidth,
                sourceHeight: depthMap.sourceHeight,
                pattern: patPixels,
                patWidth: patWidth,
                patHeight: patHeight,
                adjMin: adjMin,
                adjSafeRange: adjSafeRange,
                adjStart: adjStart,
                adjEnd: adjEnd,
                transform: depthMap.transform,
                params: StereogramKernelParams(
                    width: width,
                    height: height,
                    vwidth: vwidth,
                    oversam: oversam,
                    vmaxsep: vmaxsep,
                    s: s,
                    poffset: poffset,
                    yShift: yShift,
                    maxdepthF: maxdepthF,
                    depthRange: depthRange,
                    veyeSepF: veyeSepF,
                    obsDistF: obsDistF,
                    invert: invert
                )
            ) {
                return createImage(from: outPixels, width: width, height: height)
            }
        }

        // CPU fallback path: requires resampled depth.
        let depths = depthMap.adjustedDepthValues(width: width, height: height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        DispatchQueue.concurrentPerform(iterations: height) { y in
            var lookL = [Int](repeating: 0, count: vwidth)
            var lookR = [Int](repeating: 0, count: vwidth)
            var colour = [UInt8](repeating: 0, count: vwidth * 4)
            var empty = [UInt8](repeating: 0, count: vwidth)

            for x in 0..<vwidth {
                lookL[x] = x
                lookR[x] = x
            }

            // --- 1. Linking pass (TIW + Steer hidden-surface removal) ---
            Self.linkingPass(
                y: y,
                width: width,
                vwidth: vwidth,
                oversam: oversam,
                depths: depths,
                invert: invert,
                maxdepthF: maxdepthF,
                depthRange: depthRange,
                veyeSepF: veyeSepF,
                obsDistF: obsDistF,
                lookL: &lookL,
                lookR: &lookR
            )

            // --- 2. Pattern application: centre to right ---
            var lastlinked = -10
            for x in s..<vwidth {
                let dst = x * 4
                if lookL[x] == x || lookL[x] < s {
                    if lastlinked == x - 1 {
                        empty[x] = 1
                    } else {
                        let px = (((x + poffset) % vmaxsep) / oversam) % patWidth
                        let row = (y + ((x - s) / vmaxsep) * yShift) % patHeight
                        let pp = (row * patWidth + px) * 4
                        empty[x] = 0
                        colour[dst]     = patPixels[pp]
                        colour[dst + 1] = patPixels[pp + 1]
                        colour[dst + 2] = patPixels[pp + 2]
                    }
                } else {
                    empty[x] = empty[lookL[x]]
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
                            empty[x] = 1
                        } else {
                            let px = (((x + poffset) % vmaxsep) / oversam) % patWidth
                            let row = (y + ((s - x) / vmaxsep + 1) * yShift) % patHeight
                            let pp = (row * patWidth + px) * 4
                            empty[x] = 0
                            colour[dst]     = patPixels[pp]
                            colour[dst + 1] = patPixels[pp + 1]
                            colour[dst + 2] = patPixels[pp + 2]
                        }
                    } else {
                        let src = lookR[x] * 4
                        empty[x] = empty[lookR[x]]
                        colour[dst]     = colour[src]
                        colour[dst + 1] = colour[src + 1]
                        colour[dst + 2] = colour[src + 2]
                        lastlinked = x
                    }
                    colour[dst + 3] = 255
                    x -= 1
                }
            }

            // --- 3b. Fill contiguous empty runs with OKLab gradient between boundary colours ---
            Self.fillEmptyRunsOKLab(colour: &colour, empty: empty, vwidth: vwidth)

            // --- 4. Downsample virtual pixels into real output pixels (OKLab averaging) ---
            let rowOffset = y * width * 4
            let invOver: Float = 1.0 / Float(oversam)
            for xr in 0..<width {
                let baseV = xr * oversam
                let oi = rowOffset + xr * 4
                if oversam == 1 {
                    let p = baseV * 4
                    pixels[oi]     = colour[p]
                    pixels[oi + 1] = colour[p + 1]
                    pixels[oi + 2] = colour[p + 2]
                } else {
                    let (r, g, b) = Self.averageOKLab(colour: colour, baseV: baseV, oversam: oversam, invOver: invOver)
                    pixels[oi]     = r
                    pixels[oi + 1] = g
                    pixels[oi + 2] = b
                }
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

    // MARK: - Linking Pass

    @inline(__always)
    private static func linkingPass(
        y: Int,
        width: Int,
        vwidth: Int,
        oversam: Int,
        depths: [Float],
        invert: Bool,
        maxdepthF: Float,
        depthRange: Float,
        veyeSepF: Float,
        obsDistF: Float,
        lookL: inout [Int],
        lookR: inout [Int]
    ) {
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
    }

    // MARK: - Color Space (OKLab, Ottosson 2020)

    private static let srgbToLinearLUT: [Float] = (0..<256).map { i in
        let c = Double(i) / 255.0
        let linear = c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        return Float(linear)
    }

    private static let linearToSrgbLUT: [UInt8] = (0..<4096).map { i in
        let c = Double(i) / 4095.0
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055
        return UInt8(max(0, min(255, (s * 255.0).rounded())))
    }

    @inline(__always)
    private static func linearToSrgbByte(_ c: Float) -> UInt8 {
        let clamped = max(0, min(1, c))
        return linearToSrgbLUT[Int((clamped * 4095.0).rounded())]
    }

    @inline(__always)
    private static func srgbBytesToOKLab(_ r8: UInt8, _ g8: UInt8, _ b8: UInt8) -> (Float, Float, Float) {
        let lr = srgbToLinearLUT[Int(r8)]
        let lg = srgbToLinearLUT[Int(g8)]
        let lb = srgbToLinearLUT[Int(b8)]
        let l = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb
        let lp = cbrtf(l)
        let mp = cbrtf(m)
        let sp = cbrtf(s)
        return (
            0.2104542553 * lp + 0.7936177850 * mp - 0.0040720468 * sp,
            1.9779984951 * lp - 2.4285922050 * mp + 0.4505937099 * sp,
            0.0259040371 * lp + 0.7827717662 * mp - 0.8086757660 * sp
        )
    }

    @inline(__always)
    private static func oklabToSrgbBytes(_ L: Float, _ A: Float, _ B: Float) -> (UInt8, UInt8, UInt8) {
        let lp = L + 0.3963377774 * A + 0.2158037573 * B
        let mp = L - 0.1055613458 * A - 0.0638541728 * B
        let sp = L - 0.0894841775 * A - 1.2914855480 * B
        let l = lp * lp * lp
        let m = mp * mp * mp
        let s = sp * sp * sp
        let lr =  4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return (linearToSrgbByte(lr), linearToSrgbByte(lg), linearToSrgbByte(lb))
    }

    @inline(__always)
    private static func averageOKLab(colour: [UInt8], baseV: Int, oversam: Int, invOver: Float) -> (UInt8, UInt8, UInt8) {
        var sumL: Float = 0
        var sumA: Float = 0
        var sumB: Float = 0
        for i in 0..<oversam {
            let p = (baseV + i) * 4
            let (l, a, b) = srgbBytesToOKLab(colour[p], colour[p + 1], colour[p + 2])
            sumL += l
            sumA += a
            sumB += b
        }
        return oklabToSrgbBytes(sumL * invOver, sumA * invOver, sumB * invOver)
    }

    @inline(__always)
    private static func fillEmptyRunsOKLab(colour: inout [UInt8], empty: [UInt8], vwidth: Int) {
        var x = 0
        while x < vwidth {
            if empty[x] == 0 {
                x += 1
                continue
            }
            var end = x
            while end + 1 < vwidth && empty[end + 1] == 1 {
                end += 1
            }
            let runLen = end - x + 1
            let hasLeft = x > 0
            let hasRight = end + 1 < vwidth

            if hasLeft && hasRight {
                let lp = (x - 1) * 4
                let rp = (end + 1) * 4
                let (lL, lA, lB) = srgbBytesToOKLab(colour[lp], colour[lp + 1], colour[lp + 2])
                let (rL, rA, rB) = srgbBytesToOKLab(colour[rp], colour[rp + 1], colour[rp + 2])
                let denom = Float(runLen + 1)
                for i in 0..<runLen {
                    let t = Float(i + 1) / denom
                    let (r, g, b) = oklabToSrgbBytes(
                        lL + (rL - lL) * t,
                        lA + (rA - lA) * t,
                        lB + (rB - lB) * t
                    )
                    let p = (x + i) * 4
                    colour[p]     = r
                    colour[p + 1] = g
                    colour[p + 2] = b
                }
            } else if hasLeft || hasRight {
                let sp = hasLeft ? (x - 1) * 4 : (end + 1) * 4
                let r = colour[sp], g = colour[sp + 1], b = colour[sp + 2]
                for i in 0..<runLen {
                    let p = (x + i) * 4
                    colour[p]     = r
                    colour[p + 1] = g
                    colour[p + 2] = b
                }
            }
            x = end + 1
        }
    }

    // MARK: - Image Creation

    private func createImage(from pixels: [UInt8], width: Int, height: Int) -> PlatformImage {
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
}
