import BikeGoGoCore
import Combine
import CoreLocation
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
    @Published private(set) var activeEnergyKilocalories: Double = 0
    @Published private(set) var cadenceRPM: Double = 0
    @Published private(set) var cyclingPowerWatts: Double = 0
    @Published private(set) var elevationGainMeters: Double = 0
    @Published private(set) var errorMessage: String?

    private static let lapDistanceMeters = 5_000.0
    private static let minimumFinalLapDistanceMeters = 100.0

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var savedWorkout: HKWorkout?
    private var activeSegmentStartedAt: Date?
    private var activeElapsedSeconds: TimeInterval = 0
    private var workoutStartedAt: Date?
    private var timer: Timer?
    private var isFinalizing = false

    private var routeLocationBuffer: [CLLocation] = []
    private var isRouteInsertionInProgress = false
    private var insertedRoutePointCount = 0
    private var elevationAccumulator = ElevationGainAccumulator()
    private var maximumSpeedMetersPerSecond = 0.0

    private var lapEvents: [HKWorkoutEvent] = []
    private var lapStartedAt: Date?
    private var lapStartDistanceMeters = 0.0
    private var nextLapDistanceMeters = lapDistanceMeters

    var onMetricsChanged: ((TimeInterval, Double, Double, Double, Double, Double, Double) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5
    }

    var elapsedText: String {
        let total = Int(elapsedSeconds)
        if total >= 3_600 {
            return String(format: "%d:%02d:%02d", total / 3_600, (total % 3_600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
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

    var activeEnergyText: String {
        activeEnergyKilocalories > 0 ? String(Int(activeEnergyKilocalories.rounded())) : "--"
    }

    var cadenceText: String {
        cadenceRPM > 0 ? String(Int(cadenceRPM.rounded())) : "--"
    }

    var powerText: String {
        cyclingPowerWatts > 0 ? String(Int(cyclingPowerWatts.rounded())) : "--"
    }

    var elevationGainText: String {
        String(Int(elevationGainMeters.rounded()))
    }

    func dismissError() {
        errorMessage = nil
    }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let routeType = HKSeriesType.workoutRoute()
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            routeType
        ]

        var typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            routeType
        ]
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .distanceCycling,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .cyclingSpeed,
            .cyclingCadence,
            .cyclingPower
        ]
        typesToRead.formUnion(
            quantityIdentifiers.compactMap(HKQuantityType.quantityType(forIdentifier:))
        )

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
            builder.shouldCollectWorkoutEvents = true

            session.delegate = self
            builder.delegate = self

            let startedAt = Date()
            self.session = session
            self.builder = builder
            self.routeBuilder = builder.seriesBuilder(
                for: HKSeriesType.workoutRoute()
            ) as? HKWorkoutRouteBuilder
            self.activeElapsedSeconds = 0
            self.activeSegmentStartedAt = startedAt
            self.workoutStartedAt = startedAt
            self.lapStartedAt = startedAt
            self.elapsedSeconds = 0
            self.distanceMeters = 0
            self.heartRate = 0
            self.speedMetersPerSecond = 0
            self.activeEnergyKilocalories = 0
            self.cadenceRPM = 0
            self.cyclingPowerWatts = 0
            self.elevationGainMeters = 0
            self.maximumSpeedMetersPerSecond = 0
            self.hasStarted = true
            self.isRunning = true
            self.errorMessage = nil

            startLocationUpdates()
            session.startActivity(with: startedAt)
            builder.beginCollection(withStart: startedAt) { success, error in
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
        guard hasStarted, !isFinalizing else { return }
        activeElapsedSeconds = currentElapsedDuration()
        elapsedSeconds = activeElapsedSeconds
        activeSegmentStartedAt = nil
        session?.end()
        isRunning = false
        timer?.invalidate()
        publishMetrics()
    }

    private func startLocationUpdates() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            errorMessage = "手表定位权限未开启，本次训练将不会保存路线和爬升。"
        @unknown default:
            break
        }
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
        onMetricsChanged?(
            elapsedSeconds,
            distanceMeters,
            heartRate,
            speedMetersPerSecond,
            activeEnergyKilocalories,
            cadenceRPM,
            cyclingPowerWatts
        )
    }

    private func finishWorkout(at date: Date) {
        guard !isFinalizing else { return }
        guard let builder else {
            resetWorkout()
            return
        }

        isFinalizing = true
        locationManager.stopUpdatingLocation()
        appendFinalLapIfNeeded(at: date)
        flushRouteData(force: true)

        addLapEvents(to: builder) { [weak self] in
            self?.addWorkoutMetadata(to: builder) { [weak self] in
                self?.endCollectionAndSave(builder: builder, at: date)
            }
        }
    }

    private func addLapEvents(
        to builder: HKLiveWorkoutBuilder,
        completion: @escaping () -> Void
    ) {
        guard !lapEvents.isEmpty else {
            completion()
            return
        }

        builder.addWorkoutEvents(lapEvents) { success, error in
            Task { @MainActor in
                if !success, let error {
                    self.errorMessage = "保存骑行分段失败：\(error.localizedDescription)"
                }
                completion()
            }
        }
    }

    private func addWorkoutMetadata(
        to builder: HKLiveWorkoutBuilder,
        completion: @escaping () -> Void
    ) {
        let averageSpeed = elapsedSeconds > 0 ? distanceMeters / elapsedSeconds : 0
        let speedUnit = HKUnit.meter().unitDivided(by: .second())
        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "BikeGoGo",
            HKMetadataKeyIndoorWorkout: false,
            HKMetadataKeyTimeZone: TimeZone.current.identifier,
            HKMetadataKeyElevationAscended: HKQuantity(
                unit: .meter(),
                doubleValue: elevationGainMeters
            ),
            HKMetadataKeyAverageSpeed: HKQuantity(
                unit: speedUnit,
                doubleValue: averageSpeed
            ),
            HKMetadataKeyMaximumSpeed: HKQuantity(
                unit: speedUnit,
                doubleValue: maximumSpeedMetersPerSecond
            )
        ]

        builder.addMetadata(metadata) { success, error in
            Task { @MainActor in
                if !success, let error {
                    self.errorMessage = "保存训练统计失败：\(error.localizedDescription)"
                }
                completion()
            }
        }
    }

    private func endCollectionAndSave(builder: HKLiveWorkoutBuilder, at date: Date) {
        builder.endCollection(withEnd: date) { success, error in
            guard success else {
                Task { @MainActor in
                    self.errorMessage = "结束训练失败：\(error?.localizedDescription ?? "未知错误")"
                    self.resetWorkout()
                }
                return
            }

            builder.finishWorkout { workout, error in
                Task { @MainActor in
                    if let error {
                        self.errorMessage = "保存训练失败：\(error.localizedDescription)"
                        self.resetWorkout()
                        return
                    }
                    guard let workout else {
                        self.errorMessage = "训练已结束，但 HealthKit 没有返回训练记录。"
                        self.resetWorkout()
                        return
                    }

                    self.savedWorkout = workout
                    self.finishSavedRouteIfReady()
                }
            }
        }
    }

    private func appendCompletedLapsIfNeeded(at date: Date) {
        while distanceMeters >= nextLapDistanceMeters {
            appendLap(
                endingAt: date,
                endingDistanceMeters: nextLapDistanceMeters
            )
            nextLapDistanceMeters += Self.lapDistanceMeters
        }
    }

    private func appendFinalLapIfNeeded(at date: Date) {
        let remainingDistance = distanceMeters - lapStartDistanceMeters
        guard remainingDistance >= Self.minimumFinalLapDistanceMeters else { return }
        appendLap(endingAt: date, endingDistanceMeters: distanceMeters)
    }

    private func appendLap(endingAt date: Date, endingDistanceMeters: Double) {
        guard let lapStartedAt else { return }
        let lapDistance = max(endingDistanceMeters - lapStartDistanceMeters, 0)
        let lapDuration = max(date.timeIntervalSince(lapStartedAt), 0)
        guard lapDistance > 0, lapDuration > 0 else { return }

        let speedUnit = HKUnit.meter().unitDivided(by: .second())
        let event = HKWorkoutEvent(
            type: .lap,
            dateInterval: DateInterval(start: lapStartedAt, end: date),
            metadata: [
                HKMetadataKeyLapLength: HKQuantity(unit: .meter(), doubleValue: lapDistance),
                HKMetadataKeyAverageSpeed: HKQuantity(
                    unit: speedUnit,
                    doubleValue: lapDistance / lapDuration
                )
            ]
        )
        lapEvents.append(event)
        self.lapStartedAt = date
        lapStartDistanceMeters = endingDistanceMeters
    }

    private func handleLocations(_ locations: [CLLocation]) {
        guard hasStarted, isRunning, !isFinalizing else { return }
        let earliestTimestamp = workoutStartedAt?.addingTimeInterval(-5) ?? .distantPast
        let now = Date()
        let accepted = locations.filter { location in
            location.timestamp >= earliestTimestamp
                && now.timeIntervalSince(location.timestamp) <= 15
                && location.horizontalAccuracy >= 0
                && location.horizontalAccuracy <= 35
        }
        guard !accepted.isEmpty else { return }

        for location in accepted {
            elevationAccumulator.add(
                altitudeMeters: location.altitude,
                verticalAccuracyMeters: location.verticalAccuracy
            )
            elevationGainMeters = elevationAccumulator.elevationGainMeters

            let hasUsableSpeedAccuracy = location.speedAccuracy < 0 || location.speedAccuracy <= 3
            if location.speed >= 0, hasUsableSpeedAccuracy {
                maximumSpeedMetersPerSecond = max(maximumSpeedMetersPerSecond, location.speed)
            }
        }

        routeLocationBuffer.append(contentsOf: accepted)
        if routeLocationBuffer.count >= 5 {
            flushRouteData()
        }
    }

    private func flushRouteData(force: Bool = false) {
        guard let routeBuilder,
              !isRouteInsertionInProgress,
              !routeLocationBuffer.isEmpty,
              force || routeLocationBuffer.count >= 5 else {
            finishSavedRouteIfReady()
            return
        }

        let batch = routeLocationBuffer
        routeLocationBuffer.removeAll(keepingCapacity: true)
        isRouteInsertionInProgress = true
        routeBuilder.insertRouteData(batch) { success, error in
            Task { @MainActor in
                self.isRouteInsertionInProgress = false
                if success {
                    self.insertedRoutePointCount += batch.count
                } else if let error {
                    self.errorMessage = "部分骑行路线保存失败：\(error.localizedDescription)"
                }

                self.flushRouteData(force: self.isFinalizing)
                self.finishSavedRouteIfReady()
            }
        }
    }

    private func finishSavedRouteIfReady() {
        guard isFinalizing, let workout = savedWorkout else { return }
        guard !isRouteInsertionInProgress else { return }
        if !routeLocationBuffer.isEmpty {
            flushRouteData(force: true)
            return
        }

        guard insertedRoutePointCount > 0, let routeBuilder else {
            resetWorkout()
            return
        }

        let metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "BikeGoGo",
            HKMetadataKeyTimeZone: TimeZone.current.identifier
        ]
        savedWorkout = nil
        routeBuilder.finishRoute(with: workout, metadata: metadata) { route, error in
            Task { @MainActor in
                if route == nil, let error {
                    self.errorMessage = "训练已保存，但路线关联失败：\(error.localizedDescription)"
                }
                self.resetWorkout()
            }
        }
    }

    private func resetWorkout() {
        timer?.invalidate()
        timer = nil
        locationManager.stopUpdatingLocation()
        session = nil
        builder = nil
        routeBuilder = nil
        savedWorkout = nil
        activeSegmentStartedAt = nil
        workoutStartedAt = nil
        hasStarted = false
        isRunning = false
        isFinalizing = false
        routeLocationBuffer.removeAll()
        isRouteInsertionInProgress = false
        insertedRoutePointCount = 0
        elevationAccumulator = ElevationGainAccumulator()
        lapEvents.removeAll()
        lapStartedAt = nil
        lapStartDistanceMeters = 0
        nextLapDistanceMeters = Self.lapDistanceMeters
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
        Task { @MainActor in
            errorMessage = "训练会话失败：\(error.localizedDescription)"
            resetWorkout()
        }
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
            appendCompletedLapsIfNeeded(at: Date())
            publishMetrics()

        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            activeEnergyKilocalories = statistics.sumQuantity()?.doubleValue(
                for: .kilocalorie()
            ) ?? activeEnergyKilocalories

        case HKQuantityTypeIdentifier.cyclingSpeed.rawValue:
            let unit = HKUnit.meter().unitDivided(by: .second())
            speedMetersPerSecond = statistics.mostRecentQuantity()?.doubleValue(
                for: unit
            ) ?? speedMetersPerSecond

        case HKQuantityTypeIdentifier.cyclingCadence.rawValue:
            let unit = HKUnit.count().unitDivided(by: .minute())
            cadenceRPM = statistics.mostRecentQuantity()?.doubleValue(
                for: unit
            ) ?? cadenceRPM

        case HKQuantityTypeIdentifier.cyclingPower.rawValue:
            cyclingPowerWatts = statistics.mostRecentQuantity()?.doubleValue(
                for: .watt()
            ) ?? cyclingPowerWatts

        default:
            break
        }
    }
}

extension WatchWorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard hasStarted else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                errorMessage = "手表定位权限未开启，本次训练将不会保存路线和爬升。"
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            handleLocations(locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        Task { @MainActor in
            errorMessage = "手表定位暂时不可用：\(error.localizedDescription)"
        }
    }
}
