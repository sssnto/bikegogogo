import Combine
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
    @Published private(set) var errorMessage: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var activeSegmentStartedAt: Date?
    private var activeElapsedSeconds: TimeInterval = 0
    private var timer: Timer?
    var onMetricsChanged: ((TimeInterval, Double, Double, Double) -> Void)?

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
            errorMessage = "HealthKit 授权失败：\(error.localizedDescription)"
        }
    }

    func startWorkout(configuration providedConfiguration: HKWorkoutConfiguration? = nil) {
        guard !hasStarted else { return }

        let configuration: HKWorkoutConfiguration
        if let providedConfiguration {
            configuration = providedConfiguration
        } else {
            configuration = HKWorkoutConfiguration()
            configuration.activityType = .cycling
            configuration.locationType = .outdoor
        }

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
            self.activeElapsedSeconds = 0
            self.activeSegmentStartedAt = Date()
            self.elapsedSeconds = 0
            self.distanceMeters = 0
            self.heartRate = 0
            self.speedMetersPerSecond = 0
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
            errorMessage = "无法开始骑行训练：\(error.localizedDescription)"
        }
    }

    func pauseWorkout() {
        guard isRunning else { return }
        activeElapsedSeconds = currentElapsedDuration()
        activeSegmentStartedAt = nil
        session?.pause()
        isRunning = false
        publishMetrics()
    }

    func resumeWorkout() {
        guard hasStarted, !isRunning else { return }
        activeSegmentStartedAt = Date()
        session?.resume()
        isRunning = true
    }

    func endWorkout() {
        guard hasStarted else { return }
        activeElapsedSeconds = currentElapsedDuration()
        activeSegmentStartedAt = nil
        session?.end()
        isRunning = false
        timer?.invalidate()
        publishMetrics()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                self.elapsedSeconds = self.currentElapsedDuration()
                self.publishMetrics()
            }
        }
    }

    private func currentElapsedDuration(at date: Date = Date()) -> TimeInterval {
        guard let activeSegmentStartedAt else { return activeElapsedSeconds }
        return activeElapsedSeconds + max(date.timeIntervalSince(activeSegmentStartedAt), 0)
    }

    private func publishMetrics() {
        onMetricsChanged?(elapsedSeconds, distanceMeters, heartRate, speedMetersPerSecond)
    }

    private func finishWorkout(at date: Date) {
        guard let builder else {
            resetWorkout()
            return
        }

        builder.endCollection(withEnd: date) { success, error in
            guard success else {
                Task { @MainActor in
                    self.errorMessage = "结束训练失败：\(error?.localizedDescription ?? "未知错误")"
                    self.resetWorkout()
                }
                return
            }

            builder.finishWorkout { _, error in
                let errorDescription = error?.localizedDescription
                Task { @MainActor in
                    if let errorDescription {
                        self.errorMessage = "保存训练失败：\(errorDescription)"
                    }
                    self.resetWorkout()
                }
            }
        }
    }

    private func resetWorkout() {
        timer?.invalidate()
        timer = nil
        session = nil
        builder = nil
        activeSegmentStartedAt = nil
        hasStarted = false
        isRunning = false
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
            if toState == .ended {
                finishWorkout(at: date)
            }
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
            publishMetrics()

        default:
            break
        }
    }
}
