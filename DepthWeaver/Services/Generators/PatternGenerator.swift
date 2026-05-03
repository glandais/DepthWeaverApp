import CoreGraphics

protocol PatternGenerator {
    func generate(size: CGSize) -> PlatformImage
}
