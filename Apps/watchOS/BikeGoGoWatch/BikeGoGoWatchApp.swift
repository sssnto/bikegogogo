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
                    bridge.onRideStateReceived = { state in
                        switch state {
                        case "recording" where !workoutManager.hasStarted:
                            workoutManager.startWorkout()
                        case "recording" where !workoutManager.isRunning:
                            workoutManager.resumeWorkout()
                        case "paused" where workoutManager.isRunning:
                            workoutManager.pauseWorkout()
                        case "finished" where workoutManager.hasStarted:
                            workoutManager.endWorkout()
                        default:
                            break
                        }
                    }
                    workoutManager.onMetricsChanged = { elapsed, distance, heartRate, speed in
                        bridge.sendWorkoutMetrics(
                            elapsedSeconds: elapsed,
                            distanceMeters: distance,
                            heartRate: heartRate,
                            speedMetersPerSecond: speed
                        )
                    }
                    await workoutManager.requestAuthorization()
                }
        }
    }
}
