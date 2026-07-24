import Foundation
import HealthKit

@MainActor
final class WatchWorkoutManager: NSObject, ObservableObject {
    @Published private(set) var hasStarted = false
    @Published private(set) var isRunning = false
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var heartRate: Double = 0
    @Published private(set) var speedMetersPerSecond: Double = 0

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var startDate: Date?
    private var timer: Timer?

    var elapsedText: String {
        let minutes = Int(elapsedSeconds) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var distanceText: String {
        String(format: "%.2f", distanceMeters / 1_000)
    }

    var heartRateText: String {
        heartRate > 0 ? "\(Int(heartRate))" : "--"
    }

    var speedText: String {
        String(format: "%.1f", speedMetersPerSecond * 3.6)
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType()
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .distanceCycling)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        do {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            print("HealthKit authorization failed: \(error.localizedDescription)")
        }
    }

    func startWorkout() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )

            session.delegate = self
            builder.delegate = self

            self.session = session
            self.builder = builder
            self.startDate = Date()
            self.hasStarted = true
            self.isRunning = true

            session.startActivity(with: Date())
            builder.beginCollection(withStart: Date()) { success, error in
                if !success, let error {
                    print("Workout collection failed: \(error.localizedDescription)")
                }
            }
            startTimer()
        } catch {
            print("Unable to start workout: \(error.localizedDescription)")
        }
    }

    func pauseWorkout() {
        session?.pause()
        isRunning = false
    }

    func resumeWorkout() {
        session?.resume()
        isRunning = true
    }

    func endWorkout() {
        session?.end()
        isRunning = false
        hasStarted = false
        timer?.invalidate()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, let startDate = self.startDate else { return }
                self.elapsedSeconds = Date().timeIntervalSince(startDate)
            }
        }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            isRunning = toState == .running
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error.localizedDescription)")
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType else { continue }
                updateStatistics(for: quantityType)
            }
        }
    }

    private func updateStatistics(for type: HKQuantityType) {
        guard let statistics = builder?.statistics(for: type) else { return }

        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue:
            let unit = HKUnit.count().unitDivided(by: .minute())
            heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? heartRate

        case HKQuantityTypeIdentifier.distanceCycling.rawValue:
            distanceMeters = statistics.sumQuantity()?.doubleValue(for: .meter()) ?? distanceMeters
            if elapsedSeconds > 0 {
                speedMetersPerSecond = distanceMeters / elapsedSeconds
            }

        default:
            break
        }
    }
}

