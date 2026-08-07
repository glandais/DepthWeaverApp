import SwiftUI

@main
struct DepthWeaverApp: App {
    init() {
        DWFontRegistrar.registerBundledFonts()
        Task.detached(priority: .utility) {
            try? DepthAnythingService.shared.loadModel()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
        }
        #endif
    }
}
