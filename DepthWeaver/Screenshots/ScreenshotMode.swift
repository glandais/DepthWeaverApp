#if SCREENSHOTS
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The screen the app opens on in capture mode.
///
/// One launch per capture, without a single tap: the capture script never has
/// to find a button by its label, which changes from one language to the next.
enum ScreenshotScreen: String {
    /// The canvas: a finished stereogram, full bleed, with its floating chrome.
    case hero
    /// The depth-source picker, capture flows included.
    case source
    /// The Depth drawer: the current depth map as a 3D point cloud.
    case depth3d
    /// The 3D-model screen with a bundled model loaded.
    case model
    /// The Pattern drawer, with a procedural generator selected.
    case pattern
    /// The depth-adjustment screen: point cloud and range sliders.
    case adjust
    /// The Tune drawer, on the Punchy preset.
    case tune
}

/// The launch arguments that drive the App Store captures.
///
/// Compiled only in the `Screenshots` configuration (see `project.yml`): none of
/// this exists in the archived binary.
///
/// `simctl launch … -screenshotMode YES -screenshotScreen tune` writes into the
/// `NSArgumentDomain` of `UserDefaults`: there is nothing to parse. On macOS,
/// `open -n DepthWeaver.app --args -screenshotMode YES …` does the same.
///
/// Every screen is deterministic: a bundled depth map, a bundled or seeded
/// pattern, fixed settings. Nothing shown is staged beyond what a user gets by
/// picking the same preset, pattern and tab: in particular the simulator has no
/// LiDAR, so no screen pretends to show a live scan (see `depth3d`).
enum ScreenshotMode {
    static let isActive = UserDefaults.standard.bool(forKey: "screenshotMode")

    static let screen = ScreenshotScreen(
        rawValue: UserDefaults.standard.string(forKey: "screenshotScreen") ?? "") ?? .hero

    /// The bundled height map each screen opens on. Different ones, so that no
    /// two cards show the same shape.
    static var depthPreset: DepthMapPreset {
        switch screen {
        case .hero: .dolphin
        case .source: .dog
        case .depth3d: .ship
        case .model: .dog
        case .pattern: .planet
        case .adjust: .atomium
        case .tune: .thumbsUp
        }
    }

    /// The generator settings each screen opens on.
    static var settings: StereogramSettings {
        var settings = StereogramSettings()
        switch screen {
        case .hero:
            settings.patternSource = .asset(.leaves)
        case .depth3d:
            settings.patternSource = .asset(.clouds)
        case .pattern:
            // Seeded (seed 0 by default): the same stars on every launch.
            settings.patternSource = .procedural(.stars, ProceduralPatternType.stars.defaultConfig())
        case .tune:
            StereogramPreset.punchy.apply(to: &settings)
            settings.patternSource = .asset(.giraffe)
        case .source, .model, .adjust:
            break
        }
        return settings
    }

    /// Settings kept in `@AppStorage`, forced for this launch: no first-launch
    /// trainer over the canvas, no pinch hint, and on the Mac the inspector
    /// sections that tell each card's story.
    ///
    /// They go into the argument domain, which is never saved and wins over
    /// the app's own preferences: the Mac build shares its container with an
    /// installed DepthWeaver, whose settings must stay untouched.
    static func applyDefaults() {
        guard isActive else { return }
        let defaults = UserDefaults.standard
        var forced = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        forced["trainer.hasSeen"] = true
        forced["canvas.hintDismissed"] = true
        #if os(macOS)
        let expanded: (source: Bool, pattern: Bool, depth: Bool, settings: Bool) = switch screen {
        case .pattern: (false, true, false, false)
        case .tune: (false, false, true, true)
        default: (true, true, false, false)
        }
        forced["inspector.source.expanded"] = expanded.source
        forced["inspector.pattern.expanded"] = expanded.pattern
        forced["inspector.depth.expanded"] = expanded.depth
        forced["inspector.settings.expanded"] = expanded.settings
        // No window restoration: the capture window gets its own frame.
        forced["ApplePersistenceIgnoreState"] = true
        #endif
        defaults.setVolatileDomain(forced, forName: UserDefaults.argumentDomain)
    }

    // MARK: - Ready marker

    /// The file `scripts/screenshots.sh` waits for before it captures, in the
    /// app container's `tmp/`: a stereogram takes a variable time to render in
    /// Debug, and waiting on a marker beats a fixed delay that is either too
    /// short or wasted.
    ///
    /// It holds the screen name; on macOS, followed by the window number, which
    /// is the `CGWindowID` that `screencapture -l` takes. On macOS the same line
    /// also goes to stdout, prefixed with `screenshot-ready`.
    static let readyMarker = FileManager.default.temporaryDirectory
        .appendingPathComponent("screenshot-ready")

    /// Time left to SceneKit and to the last animations once the content is in.
    static let settle: Duration = .milliseconds(1200)

    @MainActor private static var signalled = false

    @MainActor
    static func signalReady() {
        guard isActive, !signalled else { return }
        signalled = true
        var line = screen.rawValue
        #if os(macOS)
        if let window = captureWindow {
            line += " \(window.windowNumber)"
        }
        #endif
        try? Data((line + "\n").utf8).write(to: readyMarker, options: .atomic)
        #if os(macOS)
        // The Mac script cannot read the sandbox container (app data
        // protection), but it launches the binary itself and reads its stdout.
        print("screenshot-ready \(line)")
        fflush(stdout)
        #endif
    }

    #if os(macOS)
    /// The App Store accepts 1440 x 900 for the Mac (16:10); on a 1x display
    /// this is also the capture's pixel size, and Koubou scales the card up.
    static let windowSize = CGSize(width: 1440, height: 900)

    @MainActor
    private static var captureWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.contentViewController != nil && $0.canBecomeMain }
    }

    /// Gives the main window its fixed capture size, top-left of the main
    /// screen's visible area, and brings it to the front.
    @MainActor
    static func stageWindow() {
        guard isActive, let window = captureWindow else { return }
        let visible = (NSScreen.main ?? window.screen)?.visibleFrame ?? .zero
        let frame = NSRect(
            x: visible.minX + 40,
            y: visible.maxY - 40 - windowSize.height,
            width: windowSize.width,
            height: windowSize.height
        )
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif
}

extension View {
    /// Writes the ready marker once `isReady` holds on one of `screens`, after
    /// `settle`. A no-op outside capture mode.
    ///
    /// Screens whose content is a SceneKit view give it longer: their state is
    /// in place at once, but SceneKit's first frame (shader compilation
    /// included) comes seconds later on a loaded machine.
    func screenshotReady(
        on screens: Set<ScreenshotScreen>,
        when isReady: Bool,
        settle: Duration = ScreenshotMode.settle
    ) -> some View {
        task(id: isReady) {
            guard ScreenshotMode.isActive, screens.contains(ScreenshotMode.screen), isReady else { return }
            #if os(macOS)
            ScreenshotMode.stageWindow()
            #endif
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled else { return }
            ScreenshotMode.signalReady()
        }
    }
}

// MARK: - Launch state

extension DepthMapPreset {
    /// The height map the app opens on.
    static var launch: DepthMapPreset { ScreenshotMode.isActive ? ScreenshotMode.depthPreset : .dog }
}

extension StereogramSettings {
    /// The generator settings the canvas opens on.
    static var launch: StereogramSettings { ScreenshotMode.isActive ? ScreenshotMode.settings : StereogramSettings() }
}

#if os(iOS)
import SceneKit

extension ScreenshotMode {
    /// Turns the 3D-model camera to a three-quarter view, as a user would with
    /// one drag: a bundled model opens on its own camera, often head-on.
    @MainActor
    static func orbitModel(in view: SCNView?) {
        guard isActive, screen == .model, let view else { return }
        let controller = view.defaultCameraController
        controller.interactionMode = .orbitTurntable
        controller.rotateBy(x: -35, y: 12)
    }

    /// Capture flows only exist on LiDAR hardware, which the simulator is not.
    /// The source screen shows them as a Pro iPhone or iPad does, under the
    /// app's own "Pro · LiDAR" tag; nothing else pretends to have scanned.
    static var showsCaptureHardware: Bool { isActive && screen == .source }
}

extension DrawerState {
    /// The drawer the canvas opens with.
    static var launch: DrawerState {
        guard ScreenshotMode.isActive else { return .closed }
        return switch ScreenshotMode.screen {
        case .depth3d: .open(.depth)
        case .pattern: .open(.pattern)
        case .tune: .open(.tune)
        case .hero, .source, .model, .adjust: .closed
        }
    }
}

extension NavigationPath {
    /// The screen pushed over the canvas at launch.
    static var launch: NavigationPath {
        guard ScreenshotMode.isActive else { return NavigationPath() }
        return switch ScreenshotMode.screen {
        case .source: NavigationPath([NavigationDestination.depthSource])
        case .model: NavigationPath([NavigationDestination.model3DCapture])
        case .adjust: NavigationPath([NavigationDestination.depthAdjustment])
        case .hero, .depth3d, .pattern, .tune: NavigationPath()
        }
    }
}
#endif

#else
import SwiftUI

extension DepthMapPreset {
    static var launch: DepthMapPreset { .dog }
}

extension StereogramSettings {
    static var launch: StereogramSettings { StereogramSettings() }
}

#if os(iOS)
extension DrawerState {
    static var launch: DrawerState { .closed }
}

extension NavigationPath {
    static var launch: NavigationPath { NavigationPath() }
}
#endif
#endif
