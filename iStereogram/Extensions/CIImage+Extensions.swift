import CoreImage
import UIKit

extension UIImage.Orientation {
    /// Maps UIImage.Orientation to the EXIF orientation integer used by CIImage.
    var exifOrientation: Int {
        switch self {
        case .up:            return 1
        case .down:          return 3
        case .left:          return 8
        case .right:         return 6
        case .upMirrored:    return 2
        case .downMirrored:  return 4
        case .leftMirrored:  return 5
        case .rightMirrored: return 7
        @unknown default:    return 1
        }
    }
}

extension CIImage {
    /// Returns a resized image.
    func resized(to size: CGSize) -> CIImage {
        let outputScaleX = size.width / extent.width
        let outputScaleY = size.height / extent.height
        var outputImage = transformed(by: CGAffineTransform(scaleX: outputScaleX, y: outputScaleY))
        outputImage = outputImage.transformed(
            by: CGAffineTransform(translationX: -outputImage.extent.origin.x, y: -outputImage.extent.origin.y)
        )
        return outputImage
    }
}

extension CIContext {
    /// Renders an image to a new pixel buffer with the given format.
    func render(_ image: CIImage, pixelFormat: OSType) -> CVPixelBuffer? {
        var output: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(image.extent.width),
            Int(image.extent.height),
            pixelFormat,
            nil,
            &output
        )
        guard status == kCVReturnSuccess else { return nil }
        render(image, to: output)
        return output
    }
}
