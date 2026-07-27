import BikeGoGoCore
import SwiftUI

@main
struct BikeGoGoApp: App {
    @UIApplicationDelegateAdaptor(BikeGoGoAppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    await appState.bootstrap()
                }
        }
    }
}
