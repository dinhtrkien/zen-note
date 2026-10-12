import SwiftUI

@main
@MainActor
struct ZenNoteApp: App {
    @StateObject private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { phase in
                    if phase != .active { app.suspend() }
                }
        }
    }
}
