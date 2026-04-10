import UIKit
import simd

struct PerlinNoiseGenerator: PatternGenerator {
    let config: PerlinConfig

    func generate(size: CGSize) -> UIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        guard width > 0, height > 0 else { return UIImage() }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let freq = config.frequency
        // Radius for torus mapping — controls effective scale
        let r = 1.0 / (2.0 * .pi * Double(freq))

        var rng = SeededRNG(seed: config.seed)
        let offsetX = rng.nextDouble() * 1000
        let offsetY = rng.nextDouble() * 1000
        let offsetX2 = rng.nextDouble() * 1000
        let offsetY2 = rng.nextDouble() * 1000
        let offsetX3 = rng.nextDouble() * 1000
        let offsetY3 = rng.nextDouble() * 1000

        for y in 0..<height {
            let ny = Double(y) / Double(height)
            let angleY = ny * 2.0 * .pi

            for x in 0..<width {
                let nx = Double(x) / Double(width)
                let angleX = nx * 2.0 * .pi

                // Map 2D coordinates onto a 4D torus for seamless tiling
                let p0 = cos(angleX) * r
                let p1 = sin(angleX) * r
                let p2 = cos(angleY) * r
                let p3 = sin(angleY) * r

                let idx = (y * width + x) * 4

                switch config.colorMode {
                case .grayscale:
                    let v = fbm4D(p0 + offsetX, p1 + offsetY, p2 + offsetX2, p3 + offsetY2)
                    let byte = UInt8(clamping: Int((v * 0.5 + 0.5) * 255))
                    pixels[idx] = byte
                    pixels[idx + 1] = byte
                    pixels[idx + 2] = byte

                case .hue:
                    let v = fbm4D(p0 + offsetX, p1 + offsetY, p2 + offsetX2, p3 + offsetY2)
                    let brightness = Float(v * 0.5 + 0.5)
                    let (cr, cg, cb) = hsbToRGB(h: config.hue, s: 0.7, b: brightness)
                    pixels[idx] = UInt8(clamping: Int(cr * 255))
                    pixels[idx + 1] = UInt8(clamping: Int(cg * 255))
                    pixels[idx + 2] = UInt8(clamping: Int(cb * 255))

                case .rgb:
                    let vr = fbm4D(p0 + offsetX, p1 + offsetY, p2 + offsetX2, p3 + offsetY2)
                    let vg = fbm4D(p0 + offsetX2, p1 + offsetY2, p2 + offsetX3, p3 + offsetY3)
                    let vb = fbm4D(p0 + offsetX3, p1 + offsetY3, p2 + offsetX, p3 + offsetY)
                    pixels[idx] = UInt8(clamping: Int((vr * 0.5 + 0.5) * 255))
                    pixels[idx + 1] = UInt8(clamping: Int((vg * 0.5 + 0.5) * 255))
                    pixels[idx + 2] = UInt8(clamping: Int((vb * 0.5 + 0.5) * 255))
                }
                pixels[idx + 3] = 255
            }
        }

        return createImage(from: pixels, width: width, height: height)
    }

    // MARK: - Fractal Brownian Motion (4D)

    private func fbm4D(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Double {
        var value = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var maxAmplitude = 0.0

        for _ in 0..<config.octaves {
            value += amplitude * simplex4D(
                x * frequency, y * frequency,
                z * frequency, w * frequency
            )
            maxAmplitude += amplitude
            amplitude *= Double(config.persistence)
            frequency *= 2.0
        }

        return value / maxAmplitude
    }
}

// MARK: - 4D Simplex Noise (pure Swift)

private let grad4: [[Double]] = [
    [0,1,1,1],[0,1,1,-1],[0,1,-1,1],[0,1,-1,-1],
    [0,-1,1,1],[0,-1,1,-1],[0,-1,-1,1],[0,-1,-1,-1],
    [1,0,1,1],[1,0,1,-1],[1,0,-1,1],[1,0,-1,-1],
    [-1,0,1,1],[-1,0,1,-1],[-1,0,-1,1],[-1,0,-1,-1],
    [1,1,0,1],[1,1,0,-1],[1,-1,0,1],[1,-1,0,-1],
    [-1,1,0,1],[-1,1,0,-1],[-1,-1,0,1],[-1,-1,0,-1],
    [1,1,1,0],[1,1,-1,0],[1,-1,1,0],[1,-1,-1,0],
    [-1,1,1,0],[-1,1,-1,0],[-1,-1,1,0],[-1,-1,-1,0]
]

private let perm: [Int] = {
    let p: [Int] = [151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,
                    140,36,103,30,69,142,8,99,37,240,21,10,23,190,6,148,
                    247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,
                    57,177,33,88,237,149,56,87,174,20,125,136,171,168,68,175,
                    74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,
                    60,211,133,230,220,105,92,41,55,46,245,40,244,102,143,54,
                    65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,
                    200,196,135,130,116,188,159,86,164,100,109,198,173,186,3,64,
                    52,217,226,250,124,123,5,202,38,147,118,126,255,82,85,212,
                    207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,
                    119,248,152,2,44,154,163,70,221,153,101,155,167,43,172,9,
                    129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,
                    218,246,97,228,251,34,242,193,238,210,144,12,191,179,162,241,
                    81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,157,
                    184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,
                    222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180]
    return p + p
}()

private func dot4(_ g: [Double], _ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Double {
    g[0] * x + g[1] * y + g[2] * z + g[3] * w
}

private let F4 = (sqrt(5.0) - 1.0) / 4.0
private let G4 = (5.0 - sqrt(5.0)) / 20.0

func simplex4D(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> Double {
    let s = (x + y + z + w) * F4
    let i = Int(floor(x + s))
    let j = Int(floor(y + s))
    let k = Int(floor(z + s))
    let l = Int(floor(w + s))

    let t = Double(i + j + k + l) * G4
    let x0 = x - (Double(i) - t)
    let y0 = y - (Double(j) - t)
    let z0 = z - (Double(k) - t)
    let w0 = w - (Double(l) - t)

    // Determine simplex corners
    var rankx = 0, ranky = 0, rankz = 0, rankw = 0
    if x0 > y0 { rankx += 1 } else { ranky += 1 }
    if x0 > z0 { rankx += 1 } else { rankz += 1 }
    if x0 > w0 { rankx += 1 } else { rankw += 1 }
    if y0 > z0 { ranky += 1 } else { rankz += 1 }
    if y0 > w0 { ranky += 1 } else { rankw += 1 }
    if z0 > w0 { rankz += 1 } else { rankw += 1 }

    let i1 = rankx >= 3 ? 1 : 0, j1 = ranky >= 3 ? 1 : 0
    let k1 = rankz >= 3 ? 1 : 0, l1 = rankw >= 3 ? 1 : 0
    let i2 = rankx >= 2 ? 1 : 0, j2 = ranky >= 2 ? 1 : 0
    let k2 = rankz >= 2 ? 1 : 0, l2 = rankw >= 2 ? 1 : 0
    let i3 = rankx >= 1 ? 1 : 0, j3 = ranky >= 1 ? 1 : 0
    let k3 = rankz >= 1 ? 1 : 0, l3 = rankw >= 1 ? 1 : 0

    let x1 = x0 - Double(i1) + G4, y1 = y0 - Double(j1) + G4
    let z1 = z0 - Double(k1) + G4, w1 = w0 - Double(l1) + G4
    let x2 = x0 - Double(i2) + 2.0 * G4, y2 = y0 - Double(j2) + 2.0 * G4
    let z2 = z0 - Double(k2) + 2.0 * G4, w2 = w0 - Double(l2) + 2.0 * G4
    let x3 = x0 - Double(i3) + 3.0 * G4, y3 = y0 - Double(j3) + 3.0 * G4
    let z3 = z0 - Double(k3) + 3.0 * G4, w3 = w0 - Double(l3) + 3.0 * G4
    let x4 = x0 - 1.0 + 4.0 * G4, y4 = y0 - 1.0 + 4.0 * G4
    let z4 = z0 - 1.0 + 4.0 * G4, w4 = w0 - 1.0 + 4.0 * G4

    let ii = i & 255, jj = j & 255, kk = k & 255, ll = l & 255

    func contribution(_ gx: Double, _ gy: Double, _ gz: Double, _ gw: Double, _ gi: Int) -> Double {
        let t = 0.6 - gx * gx - gy * gy - gz * gz - gw * gw
        guard t > 0 else { return 0 }
        let t2 = t * t
        return t2 * t2 * dot4(grad4[gi % 32], gx, gy, gz, gw)
    }

    let gi0 = perm[ii + perm[jj + perm[kk + perm[ll]]]]
    let gi1 = perm[ii + i1 + perm[jj + j1 + perm[kk + k1 + perm[ll + l1]]]]
    let gi2 = perm[ii + i2 + perm[jj + j2 + perm[kk + k2 + perm[ll + l2]]]]
    let gi3 = perm[ii + i3 + perm[jj + j3 + perm[kk + k3 + perm[ll + l3]]]]
    let gi4 = perm[ii + 1 + perm[jj + 1 + perm[kk + 1 + perm[ll + 1]]]]

    let n0 = contribution(x0, y0, z0, w0, gi0)
    let n1 = contribution(x1, y1, z1, w1, gi1)
    let n2 = contribution(x2, y2, z2, w2, gi2)
    let n3 = contribution(x3, y3, z3, w3, gi3)
    let n4 = contribution(x4, y4, z4, w4, gi4)

    return 27.0 * (n0 + n1 + n2 + n3 + n4)
}

// MARK: - HSB to RGB

func hsbToRGB(h: Float, s: Float, b: Float) -> (Float, Float, Float) {
    if s == 0 { return (b, b, b) }
    let h6 = h * 6.0
    let sector = Int(h6) % 6
    let f = h6 - Float(Int(h6))
    let p = b * (1.0 - s)
    let q = b * (1.0 - s * f)
    let t = b * (1.0 - s * (1.0 - f))
    switch sector {
    case 0: return (b, t, p)
    case 1: return (q, b, p)
    case 2: return (p, b, t)
    case 3: return (p, q, b)
    case 4: return (t, p, b)
    default: return (b, p, q)
    }
}
