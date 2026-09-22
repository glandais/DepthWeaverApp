import SwiftUI

@main
struct DepthWeaverApp: App {
    /// Listens to transactions from launch: a tip approved later (Ask to Buy)
    /// or interrupted must be finished, whether the tip screen is open or not.
    @State private var tipJar: TipJar

    init() {
        let tipJar = TipJar()
        tipJar.start()
        _tipJar = State(initialValue: tipJar)
        DWFontRegistrar.registerBundledFonts()
        Task.detached(priority: .utility) {
            try? DepthAnythingService.shared.loadModel()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(tipJar)
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("menu.open") {
                    NotificationCenter.default.post(name: .depthWeaverOpenRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .saveItem) {
                Button("menu.save_image") {
                    NotificationCenter.default.post(name: .depthWeaverSaveRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("menu.copy_image") {
                    NotificationCenter.default.post(name: .depthWeaverCopyRequested, object: nil)
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("menu.toggle_inspector") {
                    NotificationCenter.default.post(name: .depthWeaverToggleInspector, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
            // The stock "DepthWeaver Help" item has no help book behind it;
            // the Help menu carries the same links as the iOS About sheet.
            CommandGroup(replacing: .help) {
                Link("about.website", destination: AppLinks.website)
                Link("about.support", destination: AppLinks.support)
                Link("about.privacy", destination: AppLinks.privacy)
                Link("about.source_code", destination: AppLinks.sourceCode)
                Divider()
                Link("about.rate", destination: AppLinks.writeReview)
                Link("about.more_apps", destination: AppLinks.developerApps)
                Divider()
                TipMenuItem()
            }
        }
        #endif

        #if os(macOS)
        // The tip screen, as its own small window: the Mac counterpart of the
        // row pushed from the iOS About sheet.
        Window(Text("tip.title"), id: TipMenuItem.windowID) {
            TipJarView(tipJar: tipJar)
                .frame(width: 420, height: 380)
        }
        .windowResizability(.contentSize)
        #endif
    }
}

#if os(macOS)
/// "Support DepthWeaver…" in the Help menu. A view of its own because
/// `openWindow` is read from the environment.
private struct TipMenuItem: View {
    static let windowID = "tips"

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("menu.tip") {
            openWindow(id: Self.windowID)
        }
    }
}
#endif
