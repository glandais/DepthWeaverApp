import CoreText
import Foundation
import os

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "Fonts")

/// Registers the bundled TTFs with CoreText at launch.
///
/// The app has no `Info.plist` on disk (`GENERATE_INFOPLIST_FILE: YES`), and
/// `UIAppFonts` is an array key the `INFOPLIST_KEY_*` bridge does not handle,
/// so runtime registration is the mechanism here. It also gives an explicit
/// success/failure signal, which is what ``DWFont/customFontsAvailable`` reads
/// back to decide whether to fall back to the system faces.
enum DWFontRegistrar {
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil),
              !urls.isEmpty else {
            logger.error("No bundled .ttf resources found — falling back to system fonts")
            return
        }

        for url in urls {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                continue
            }
            // Re-registration is expected on hot reload / previews.
            let code = CFErrorGetCode(error?.takeUnretainedValue())
            if code == CTFontManagerError.alreadyRegistered.rawValue { continue }
            logger.error("Failed to register \(url.lastPathComponent, privacy: .public): \(code)")
        }

        if !DWFont.customFontsAvailable {
            logger.error("Custom fonts registered but not resolvable — using system fallback")
        }
    }
}
