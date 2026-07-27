import Foundation
import HealthKit

final class WatchWorkoutLauncher {
    private let healthStore = HKHealthStore()

    func startOutdoorCycling() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WatchWorkoutLaunchError.healthDataUnavailable
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        let launched = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in
            healthStore.startWatchApp(with: configuration) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
        guard launched else {
            throw WatchWorkoutLaunchError.watchAppDidNotLaunch
        }
    }
}

private enum WatchWorkoutLaunchError: Error {
    case healthDataUnavailable
    case watchAppDidNotLaunch
}
