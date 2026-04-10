import SwiftUI

@main
struct iStereogramApp: App {
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
