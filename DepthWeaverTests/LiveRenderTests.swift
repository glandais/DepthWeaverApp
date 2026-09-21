import CoreGraphics
import Foundation
import Testing

/// Live mode renders at `.preview` while a finger is down and `.full` the
/// moment it lifts, and pans / zooms the depth window under the finger. These
/// pin the two things that made those swaps visible as something other than a
/// change of sharpness.
@Suite("Live rendering")
struct LiveRenderTests {

    /// The pattern repeat has to stay the same *fraction* of the output at
    /// every quality, or the coarse frame reads as a zoomed-in stereogram.
    @Test("a preview frame keeps the full render's pattern repeat, relative to its width")
    func previewKeepsRelativeBandWidth() throws {
        let depthMap = DepthMapPreset.dog.toDepthMap()
        let settings = StereogramSettings()

        func relativeBand(_ quality: StereogramQuality) -> Double {
            let (width, _) = StereogramGenerator.outputSize(for: depthMap, quality: quality)
            let scale = StereogramGenerator.renderScale(for: depthMap, quality: quality)
            let dpi = Int((Float(settings.dpi) * scale).rounded())
            let geometry = StereogramGenerator.Geometry(
                dpi: dpi,
                depthStrength: settings.depthStrength
            )
            return Double(geometry.maxsep) / Double(width)
        }

        let preview = relativeBand(.preview)
        let full = relativeBand(.full)
        #expect(StereogramGenerator.outputSize(for: depthMap, quality: .preview).width
                < StereogramGenerator.outputSize(for: depthMap, quality: .full).width,
                "the preview has to actually be cheaper, or this proves nothing")
        #expect(abs(preview - full) < 0.005,
                "preview band is \(preview) of the width, full is \(full)")
    }
}
