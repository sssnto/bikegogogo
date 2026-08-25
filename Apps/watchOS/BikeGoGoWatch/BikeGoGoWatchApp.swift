import HealthKit
import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    var onWorkoutConfiguration: ((HKWorkoutConfiguration) -> Void)?
    private var pendingWorkoutConfiguration: HKWorkoutConfiguration?

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        if let onWorkoutConfiguration {
            onWorkoutConfiguration(workoutConfiguration)
        } else {
            pendingWorkoutConfiguration = workoutConfiguration
        }
    }

    func takePendingWorkoutConfiguration() -> HKWorkoutConfiguration? {
        defer { pendingWorkoutConfiguration = nil }
        return pendingWorkoutConfiguration
    }
}

@main
struct BikeGoGoWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
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

                    appDelegate.onWorkoutConfiguration = { configuration in
                        workoutManager.startWorkout(configuration: configuration)
                    }
                    if let configuration = appDelegate.takePendingWorkoutConfiguration() {
                        workoutManager.startWorkout(configuration: configuration)
                    }

                    let applyRideState: (String) -> Void = { state in
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
                    bridge.onRideStateReceived = applyRideState
                    applyRideState(bridge.remoteRideState)

                    workoutManager.onMetricsChanged = {
                        elapsed,
                        distance,
                        heartRate,
                        speed,
                        activeEnergy,
                        cadence,
                        power in
                        bridge.sendWorkoutMetrics(
                            elapsedSeconds: elapsed,
                            distanceMeters: distance,
                            heartRate: heartRate,
                            speedMetersPerSecond: speed,
                            activeEnergyKilocalories: activeEnergy,
                            cadenceRPM: cadence,
                            cyclingPowerWatts: power
                        )
                    }
                }
        }
    }
}
