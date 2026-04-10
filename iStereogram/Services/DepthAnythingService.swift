import CoreImage
import CoreML

final class DepthAnythingService {
    static let shared = DepthAnythingService()

    private let targetSize = CGSize(width: 518, height: 392)
    private let context = CIContext()
    private var model: DepthAnythingV2SmallF16?
    private let inputPixelBuffer: CVPixelBuffer

    private init() {
        var buffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create input pixel buffer")
        }
        inputPixelBuffer = buffer
    }

    func loadModel() throws {
        guard model == nil else { return }
        model = try DepthAnythingV2SmallF16()
    }

    func estimateDepth(from image: CIImage) throws -> DepthMap {
        try loadModel()
        guard let model else {
            throw DepthEstimationError.modelNotLoaded
        }

        let resized = image.resized(to: targetSize)
        context.render(resized, to: inputPixelBuffer)

        let result = try model.prediction(image: inputPixelBuffer)
        return DepthMap(pixelBuffer: result.depth, source: .depthAnything)
    }

    enum DepthEstimationError: LocalizedError {
        case modelNotLoaded

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: "Failed to load depth estimation model"
            }
        }
    }
}
