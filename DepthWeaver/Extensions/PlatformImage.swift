import CoreGraphics
import Foundation
import SwiftUI

#if os(iOS)
import UIKit

public typealias PlatformImage = UIImage

extension PlatformImage {
    static func loadFromAssets(named name: String) -> PlatformImage? {
        UIImage(named: name)
    }

    static func loadFromBundle(name: String, ofType ext: String) -> PlatformImage? {
        for bundle in candidateBundles {
            if let path = bundle.path(forResource: name, ofType: ext) {
                return UIImage(contentsOfFile: path)
            }
        }
        return nil
    }

    var pixelSize: CGSize {
        guard let cg = cgImage else { return size }
        return CGSize(width: cg.width, height: cg.height)
    }
}

#elseif os(macOS)
import AppKit

public typealias PlatformImage = NSImage

extension PlatformImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    var cgImage: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    func pngData() -> Data? {
        guard let cg = cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cg = cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }

    static func loadFromAssets(named name: String) -> PlatformImage? {
        NSImage(named: NSImage.Name(name))
    }

    static func loadFromBundle(name: String, ofType ext: String) -> PlatformImage? {
        for bundle in candidateBundles {
            if let path = bundle.path(forResource: name, ofType: ext) {
                return NSImage(contentsOfFile: path)
            }
        }
        return nil
    }

    var pixelSize: CGSize {
        guard let cg = cgImage else { return size }
        return CGSize(width: cg.width, height: cg.height)
    }
}
#endif

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #elseif os(macOS)
        self.init(nsImage: platformImage)
        #endif
    }
}

/// Bundles to search for resources. `Bundle.main` first (production path),
/// then `Bundle.allBundles` so that logic-test bundles (where `Bundle.main`
/// is the `xctest` harness) can find resources packaged with the test target.
private var candidateBundles: [Bundle] {
    var seen = Set<String>()
    var result: [Bundle] = []
    for bundle in [Bundle.main] + Bundle.allBundles where seen.insert(bundle.bundlePath).inserted {
        result.append(bundle)
    }
    return result
}

/// Converts an HSB color (hue/saturation/brightness, all in [0..1]) to RGB
/// without depending on UIColor/NSColor.
@inline(__always)
func hsbToRGB(hue h: CGFloat, saturation s: CGFloat, brightness b: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    if s <= 0 { return (b, b, b) }
    let hh = (h.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
    let i = Int(hh)
    let f = hh - CGFloat(i)
    let p = b * (1 - s)
    let q = b * (1 - s * f)
    let t = b * (1 - s * (1 - f))
    switch i {
    case 0: return (b, t, p)
    case 1: return (q, b, p)
    case 2: return (p, b, t)
    case 3: return (p, q, b)
    case 4: return (t, p, b)
    default: return (b, p, q)
    }
}
