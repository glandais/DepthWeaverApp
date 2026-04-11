import SwiftUI

@main
struct DepthWeaverApp: App {
    init() {
        Task.detached(priority: .utility) {
            try? DepthAnythingService.shared.loadModel()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
