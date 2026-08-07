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
