import SwiftUI
import SwiftData

@main
struct MyBuddyApp: App {
    @StateObject private var appState = AppState()
    private let sharedModelContainer = AppEnvironment.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }
}
