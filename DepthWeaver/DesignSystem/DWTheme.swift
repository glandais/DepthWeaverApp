import SwiftUI

/// Design tokens for the DepthWeaver canvas-first look.
///
/// The palette is deliberately fixed rather than adaptive: the iOS app runs
/// dark-only (`.preferredColorScheme(.dark)` on `IOSContentView`) because
/// stereograms read best on a near-black ground.
enum DWColor {
    private static func srgb(_ hex: UInt32, _ opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    private static func white(_ opacity: Double) -> Color {
        Color(.sRGB, white: 1, opacity: opacity)
    }

    // Grounds
    static let ground = srgb(0x0F1130)
    static let surface = srgb(0x171A40)

    // Text
    static let text = srgb(0xF2F3F5)
    static let textSecondary = srgb(0xF2F3F5, 0.55)
    static let textTertiary = srgb(0xF2F3F5, 0.42)

    // Accents — cyan drives interaction/selection, periwinkle marks badges.
    static let cyan = srgb(0x8FD9E8)
    static let periwinkle = srgb(0x9B8CF0)
    static let cyanTint = srgb(0x8FD9E8, 0.16)
    static let cyanTintStrong = srgb(0x8FD9E8, 0.24)
    static let periwinkleTint = srgb(0x9B8CF0, 0.16)

    /// Label color for anything sitting on a `cyan` or white fill.
    static let onAccent = srgb(0x101334)

    // Glass chrome
    static let glassFill = white(0.06)
    static let glassFillRaised = white(0.09)
    static let hairline = white(0.10)
    static let hairlineStrong = white(0.14)

    // Scrims over the canvas
    static let scrim = srgb(0x0F1130, 0.85)
    static let scrimClear = srgb(0x0F1130, 0)
}

enum DWRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 12
    static let lg: CGFloat = 14
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 22
    static let hero: CGFloat = 26
    static let pill: CGFloat = 999
}

enum DWSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let section: CGFloat = 32
}

enum DWMetric {
    static let knob: CGFloat = 24
    static let track: CGFloat = 5
    static let chipHeight: CGFloat = 38
    static let iconTile: CGFloat = 40
    static let circleButton: CGFloat = 38
    static let primaryButton: CGFloat = 50
    static let trainerArc: CGFloat = 330
    static let trainerCanvas: CGFloat = 274
    /// Micro-label tracking, expressed as the `.09em` of the mockup.
    static let microTracking: CGFloat = 0.09
}
