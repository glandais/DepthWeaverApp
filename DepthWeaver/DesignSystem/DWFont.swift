import CoreText
import SwiftUI

enum DWFontWeight {
    case regular, medium, semibold, bold
}

/// Typography for the redesign: Space Grotesk for UI, IBM Plex Mono for every
/// number and for the all-caps micro-labels.
///
/// The bundled TTFs are registered at launch by ``DWFontRegistrar``. If that
/// ever fails (missing resource, corrupted file), every factory here falls back
/// to the system faces instead of silently rendering SF Pro where mono digits
/// were intended.
enum DWFont {
    // PostScript names, verified against the bundled TTFs with CoreText.
    // Space Grotesk ships no static SemiBold, so semibold maps to Bold.
    private enum PSName {
        static let uiRegular = "SpaceGrotesk-Regular"
        static let uiMedium = "SpaceGrotesk-Medium"
        static let uiBold = "SpaceGrotesk-Bold"
        static let monoRegular = "IBMPlexMono-Regular"
        static let monoMedium = "IBMPlexMono-Medium"
        static let monoSemiBold = "IBMPlexMono-SemiBold"
    }

    /// Resolved once: `CTFontCreateWithName` substitutes a fallback face when
    /// the name is unknown, so comparing the PostScript name back is the
    /// reliable probe.
    static let customFontsAvailable: Bool = {
        let font = CTFontCreateWithName(PSName.uiRegular as CFString, 12, nil)
        return (CTFontCopyPostScriptName(font) as String) == PSName.uiRegular
    }()

    private static func systemWeight(_ weight: DWFontWeight) -> Font.Weight {
        switch weight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    /// Space Grotesk (or the system face when unavailable).
    static func ui(_ size: CGFloat, _ weight: DWFontWeight = .regular) -> Font {
        guard customFontsAvailable else {
            return .system(size: size, weight: systemWeight(weight))
        }
        let name = switch weight {
        case .regular: PSName.uiRegular
        case .medium: PSName.uiMedium
        case .semibold, .bold: PSName.uiBold
        }
        return .custom(name, size: size)
    }

    /// IBM Plex Mono (or SF Mono when unavailable).
    static func mono(_ size: CGFloat, _ weight: DWFontWeight = .regular) -> Font {
        guard customFontsAvailable else {
            return .system(size: size, weight: systemWeight(weight), design: .monospaced)
        }
        let name = switch weight {
        case .regular: PSName.monoRegular
        case .medium: PSName.monoMedium
        case .semibold, .bold: PSName.monoSemiBold
        }
        return .custom(name, size: size)
    }

    // Semantic aliases — screens should reach for these, not raw sizes.
    static let heroTitle = ui(26, .semibold)
    static let screenTitle = ui(20, .semibold)
    static let cardTitle = ui(17, .semibold)
    static let sectionTitle = ui(15, .medium)
    static let body = ui(14)
    static let label = ui(13, .medium)
    static let caption = ui(11, .medium)

    static let valueMono = mono(12, .medium)
    static let microMono = mono(10)
    static let badgeMono = mono(9, .medium)
}

extension View {
    /// The `PRESET` / `START HERE` / `LEARN TO SEE IT` treatment: mono, upper
    /// case, generously tracked.
    func dwMicroLabel(color: Color = DWColor.textTertiary) -> some View {
        self
            .font(DWFont.microMono)
            .textCase(.uppercase)
            .tracking(10 * DWMetric.microTracking)
            .foregroundStyle(color)
    }

    /// Mono badge treatment used for `ESTIMATED IN 1.2s` and `PRO · LiDAR`.
    func dwBadgeLabel(color: Color = DWColor.periwinkle) -> some View {
        self
            .font(DWFont.badgeMono)
            .textCase(.uppercase)
            .tracking(9 * 0.06)
            .foregroundStyle(color)
    }
}
