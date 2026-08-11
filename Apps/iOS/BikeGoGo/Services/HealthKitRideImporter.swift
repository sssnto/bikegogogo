import BikeGoGoCore
import CoreLocation
import Foundation
import HealthKit

actor HealthKitRideImporter {
    private let healthStore = HKHealthStore()

    struct ImportResult: Sendable {
        let rides: [RideSession]
        let discoveredWorkoutCount: Int
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitRideImportError.healthDataUnavailable
        }

        var typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            quantityType(.heartRate),
            quantityType(.distanceCycling),
            quantityType(.activeEnergyBurned),
            quantityType(.basalEnergyBurned)
        ]
        if #available(iOS 17.0, *) {
            typesToRead.formUnion([
                quantityType(.cyclingSpeed),
                quantityType(.cyclingCadence),
                quantityType(.cyclingPower)
            ])
        }
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }

    func importOutdoorCyclingRides(
        since startDate: Date = Calendar.current.date(
            byAdding: .year,
            value: -1,
            to: Date()
        ) ?? .distantPast
    ) async throws -> ImportResult {
        let workouts = try await cyclingWorkouts(since: startDate)
        var rides: [RideSession] = []
        rides.reserveCapacity(workouts.count)
        for workout in workouts {
            rides.append(await ride(from: workout))
        }
        return ImportResult(
            rides: rides.sorted { $0.startedAt > $1.startedAt },
            discoveredWorkoutCount: workouts.count
        )
    }

    private func cyclingWorkouts(since startDate: Date) async throws -> [HKWorkout] {
        let datePredicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: nil,
            options: .strictStartDate
        )
        let cyclingPredicate = HKQuery.predicateForWorkouts(with: .cycling)
        let predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [datePredicate, cyclingPredicate]
        )
        let sort = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: samples as? [HKWorkout] ?? []
                    )
                }
            }
            healthStore.execute(query)
        }
    }

    private func ride(from workout: HKWorkout) async -> RideSession {
        // HealthKit workouts do not always contain every optional series. A missing
        // route or sensor stream must not discard the workout and its other data.
        async let locationsResult: [CLLocation]? = try? await routeLocations(for: workout)
        async let heartRateSamplesResult: [HKQuantitySample]? = try? await quantitySamples(
            type: quantityType(.heartRate),
            workout: workout
        )
        async let distanceResult: Double? = try? await sum(
            type: quantityType(.distanceCycling),
            unit: .meter(),
            workout: workout
        )
        async let activeEnergyResult: Double? = try? await sum(
            type: quantityType(.activeEnergyBurned),
            unit: .kilocalorie(),
            workout: workout
        )
        async let basalEnergyResult: Double? = try? await sum(
            type: quantityType(.basalEnergyBurned),
            unit: .kilocalorie(),
            startDate: workout.startDate,
            endDate: workout.endDate
        )

        let cyclingSpeedType = quantityType(.cyclingSpeed)
        let cyclingCadenceType = quantityType(.cyclingCadence)
        let cyclingPowerType = quantityType(.cyclingPower)
        async let speedSummaryResult: (average: Double?, maximum: Double?)? = try? await discreteSummary(
            type: cyclingSpeedType,
            unit: HKUnit.meter().unitDivided(by: .second()),
            workout: workout
        )
        async let cadenceSamplesResult: [HKQuantitySample]? = try? await quantitySamples(
            type: cyclingCadenceType,
            workout: workout
        )
        async let powerSamplesResult: [HKQuantitySample]? = try? await quantitySamples(
            type: cyclingPowerType,
            workout: workout
        )

        let locations = await locationsResult ?? []
        let heartRateSamples = await heartRateSamplesResult ?? []
        let cadenceSamples = await cadenceSamplesResult ?? []
        let powerSamples = await powerSamplesResult ?? []
        var points = locations.map(ridePoint(from:))
        attach(
            samples: heartRateSamples,
            unit: HKUnit.count().unitDivided(by: .minute()),
            to: &points,
            assignment: { point, value in
                point.heartRateBeatsPerMinute = Int(value.rounded())
            }
        )
        attach(
            samples: cadenceSamples,
            unit: HKUnit.count().unitDivided(by: .minute()),
            to: &points,
            assignment: { point, value in
                point.cadenceRPM = Int(value.rounded())
            }
        )
        attach(
            samples: powerSamples,
            unit: .watt(),
            to: &points,
            assignment: { point, value in
                point.cyclingPowerWatts = value
            }
        )

        let routeMetrics = RideStatisticsCalculator.metrics(for: points)
        let distanceType = quantityType(.distanceCycling)
        let activeEnergyType = quantityType(.activeEnergyBurned)
        let workoutDistance = workout.statistics(for: distanceType)?
            .sumQuantity()?
            .doubleValue(for: .meter())
        let workoutActiveEnergy = workout.statistics(for: activeEnergyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
        let distance = await distanceResult
            ?? workoutDistance
            ?? routeMetrics.distanceMeters
        let activeEnergy = await activeEnergyResult ?? workoutActiveEnergy
        let basalEnergy = await basalEnergyResult
        let speedSummary = await speedSummaryResult ?? (average: nil, maximum: nil)
        let heartRateSummary = summary(
            samples: heartRateSamples,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        let cadenceSummary = summary(
            samples: cadenceSamples,
            unit: HKUnit.count().unitDivided(by: .minute())
        )
        let powerSummary = summary(samples: powerSamples, unit: .watt())
        let movingDuration = max(workout.duration, 0)
        let elapsedDuration = max(
            workout.endDate.timeIntervalSince(workout.startDate),
            movingDuration
        )
        let speedUnit = HKUnit.meter().unitDivided(by: .second())
        let metadataAverageSpeed = metadataQuantity(
            workout.metadata?[HKMetadataKeyAverageSpeed],
            unit: speedUnit
        )
        let metadataMaximumSpeed = metadataQuantity(
            workout.metadata?[HKMetadataKeyMaximumSpeed],
            unit: speedUnit
        )
        let elevationGain = metadataQuantity(
            workout.metadata?[HKMetadataKeyElevationAscended],
            unit: .meter()
        ) ?? routeMetrics.elevationGainMeters

        return RideSession(
            id: workout.uuid,
            title: "户外单车",
            state: .finished,
            source: .appleWatch,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            points: points,
            metrics: RideMetrics(
                distanceMeters: distance,
                movingDurationSeconds: movingDuration,
                elapsedDurationSeconds: elapsedDuration,
                averageSpeedMetersPerSecond: speedSummary.average
                    ?? metadataAverageSpeed
                    ?? (movingDuration > 0 ? distance / movingDuration : 0),
                maxSpeedMetersPerSecond: speedSummary.maximum
                    ?? metadataMaximumSpeed
                    ?? routeMetrics.maxSpeedMetersPerSecond,
                elevationGainMeters: elevationGain,
                averageHeartRate: heartRateSummary.average.map { Int($0.rounded()) },
                maxHeartRate: heartRateSummary.maximum.map { Int($0.rounded()) },
                activeEnergyKilocalories: activeEnergy,
                totalEnergyKilocalories: totalEnergy(
                    active: activeEnergy,
                    basal: basalEnergy
                ),
                averageCadenceRPM: cadenceSummary.average,
                maxCadenceRPM: cadenceSummary.maximum,
                averageCyclingPowerWatts: powerSummary.average,
                maxCyclingPowerWatts: powerSummary.maximum
            )
        )
    }

    private func routeLocations(for workout: HKWorkout) async throws -> [CLLocation] {
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation {
            continuation in
            let query = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: samples as? [HKWorkoutRoute] ?? []
                    )
                }
            }
            healthStore.execute(query)
        }

        var allLocations: [CLLocation] = []
        for route in routes {
            allLocations.append(contentsOf: try await locations(for: route))
        }
        return allLocations.sorted { $0.timestamp < $1.timestamp }
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var locations: [CLLocation] = []
            var hasFinished = false
            let query = HKWorkoutRouteQuery(route: route) { _, batch, done, error in
                guard !hasFinished else { return }
                if let error {
                    hasFinished = true
                    continuation.resume(throwing: error)
                    return
                }
                locations.append(contentsOf: batch ?? [])
                if done {
                    hasFinished = true
                    continuation.resume(returning: locations)
                }
            }
            healthStore.execute(query)
        }
    }

    private func quantitySamples(
        type: HKQuantityType,
        workout: HKWorkout
    ) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(
                    key: HKSampleSortIdentifierStartDate,
                    ascending: true
                )]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: samples as? [HKQuantitySample] ?? []
                    )
                }
            }
            healthStore.execute(query)
        }
    }

    private func sum(
        type: HKQuantityType,
        unit: HKUnit,
        workout: HKWorkout
    ) async throws -> Double? {
        let statistics = try await statistics(
            type: type,
            options: .cumulativeSum,
            workout: workout
        )
        return statistics?.sumQuantity()?.doubleValue(for: unit)
    }

    private func sum(
        type: HKQuantityType,
        unit: HKUnit,
        startDate: Date,
        endDate: Date
    ) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: []
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: statistics?.sumQuantity()?.doubleValue(for: unit)
                    )
                }
            }
            healthStore.execute(query)
        }
    }

    private func discreteSummary(
        type: HKQuantityType,
        unit: HKUnit,
        workout: HKWorkout
    ) async throws -> (average: Double?, maximum: Double?) {
        let statistics = try await statistics(
            type: type,
            options: [.discreteAverage, .discreteMax],
            workout: workout
        )
        return (
            statistics?.averageQuantity()?.doubleValue(for: unit),
            statistics?.maximumQuantity()?.doubleValue(for: unit)
        )
    }

    private func statistics(
        type: HKQuantityType,
        options: HKStatisticsOptions,
        workout: HKWorkout
    ) async throws -> HKStatistics? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: options
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics)
                }
            }
            healthStore.execute(query)
        }
    }

    private func attach(
        samples: [HKQuantitySample],
        unit: HKUnit,
        to points: inout [RidePoint],
        assignment: (inout RidePoint, Double) -> Void
    ) {
        guard !points.isEmpty, !samples.isEmpty else { return }
        var sampleIndex = 0
        for pointIndex in points.indices {
            while sampleIndex + 1 < samples.count,
                  abs(samples[sampleIndex + 1].startDate.timeIntervalSince(
                      points[pointIndex].timestamp
                  )) < abs(samples[sampleIndex].startDate.timeIntervalSince(
                      points[pointIndex].timestamp
                  )) {
                sampleIndex += 1
            }
            let sample = samples[sampleIndex]
            guard abs(sample.startDate.timeIntervalSince(points[pointIndex].timestamp)) <= 30 else {
                continue
            }
            assignment(
                &points[pointIndex],
                sample.quantity.doubleValue(for: unit)
            )
        }
    }

    private func summary(
        samples: [HKQuantitySample],
        unit: HKUnit
    ) -> (average: Double?, maximum: Double?) {
        let values = samples.map { $0.quantity.doubleValue(for: unit) }
        guard !values.isEmpty else { return (nil, nil) }
        return (values.reduce(0, +) / Double(values.count), values.max())
    }

    private func ridePoint(from location: CLLocation) -> RidePoint {
        RidePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            elevationMeters: location.verticalAccuracy >= 0 ? location.altitude : nil,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            courseDegrees: location.course >= 0 ? location.course : nil,
            horizontalAccuracyMeters: location.horizontalAccuracy >= 0
                ? location.horizontalAccuracy
                : nil,
            timestamp: location.timestamp
        )
    }

    private func metadataQuantity(_ value: Any?, unit: HKUnit) -> Double? {
        (value as? HKQuantity)?.doubleValue(for: unit)
    }

    private func totalEnergy(active: Double?, basal: Double?) -> Double? {
        guard active != nil || basal != nil else { return nil }
        return (active ?? 0) + (basal ?? 0)
    }

    private func quantityType(_ identifier: HKQuantityTypeIdentifier) -> HKQuantityType {
        HKObjectType.quantityType(forIdentifier: identifier)!
    }
}

private enum HealthKitRideImportError: LocalizedError {
    case healthDataUnavailable

    var errorDescription: String? {
        "此设备不支持 Apple 健康数据。"
    }
}
