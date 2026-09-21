#if os(iOS)
import Foundation

/// The three groups of controls reachable from the floating bar.
enum ToolTab: String, CaseIterable, Identifiable {
    case depth
    case pattern
    case tune

    var id: String { rawValue }

    var title: String.LocalizationValue {
        switch self {
        case .depth: "canvas.tool_depth"
        case .pattern: "canvas.tool_pattern"
        case .tune: "canvas.tool_tune"
        }
    }

    var systemImage: String {
        switch self {
        case .depth: "square.3.layers.3d"
        case .pattern: "circle.grid.2x2"
        case .tune: "slider.horizontal.3"
        }
    }
}

/// What a gesture on the canvas moves.
///
/// The stereogram is a render of a depth source, and both are worth touching:
/// `.view` inspects the finished image, `.live` reaches past it and moves the
/// source — the depth map itself, or the 3D model behind it — regenerating the
/// illusion as the finger travels.
enum CanvasMode: String, CaseIterable, Identifiable {
    case view
    case live

    var id: String { rawValue }

    var title: String.LocalizationValue {
        switch self {
        case .view: "canvas.mode_view"
        case .live: "canvas.mode_live"
        }
    }

    var systemImage: String {
        switch self {
        case .view: "arrow.up.left.and.down.right.magnifyingglass"
        case .live: "move.3d"
        }
    }
}

enum DrawerState: Equatable {
    case closed
    case open(ToolTab)

    var openTab: ToolTab? {
        if case .open(let tab) = self { return tab }
        return nil
    }

    var isOpen: Bool { openTab != nil }

    /// Tapping a chip opens its tab, or closes the drawer if that tab is
    /// already showing.
    mutating func toggle(_ tab: ToolTab) {
        self = openTab == tab ? .closed : .open(tab)
    }
}
#endif
