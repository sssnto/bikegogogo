import SwiftUI

@main
struct BikeGoGoWatchApp: App {
    @StateObject private var workoutManager = WatchWorkoutManager()
    @StateObject private var bridge = WatchSessionBridge()

    var body: some Scene {
        WindowGroup {
            WatchRideView()
                .environmentObject(workoutManager)
                .environmentObject(bridge)
                .task {
                    bridge.activate()
                    await workoutManager.requestAuthorization()
                }
        }
    }
}

