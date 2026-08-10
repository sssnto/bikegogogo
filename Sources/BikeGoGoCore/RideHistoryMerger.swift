import Foundation

public enum RideHistoryMerger {
    public static func merging(
        existing: [RideSession],
        imported: [RideSession]
    ) -> [RideSession] {
        var merged = existing

        for importedRide in imported {
            if let index = merged.firstIndex(where: { $0.id == importedRide.id }) {
                merged[index] = enriched(importedRide, preserving: merged[index])
            } else if let index = merged.firstIndex(where: {
                representsSameWorkout($0, importedRide)
            }) {
                var replacement = enriched(importedRide, preserving: merged[index])
                replacement.id = merged[index].id
                replacement.source = .merged
                merged[index] = replacement
            } else {
                merged.append(importedRide)
            }
        }

        return merged.sorted { $0.startedAt > $1.startedAt }
    }

    public static func representsSameWorkout(
        _ first: RideSession,
        _ second: RideSession
    ) -> Bool {
        let startDifference = abs(first.startedAt.timeIntervalSince(second.startedAt))
        guard startDifference <= 5 * 60 else { return false }

        let firstEnd = first.endedAt
            ?? first.startedAt.addingTimeInterval(first.metrics.elapsedDurationSeconds)
        let secondEnd = second.endedAt
            ?? second.startedAt.addingTimeInterval(second.metrics.elapsedDurationSeconds)
        let overlap = min(firstEnd, secondEnd).timeIntervalSince(
            max(first.startedAt, second.startedAt)
        )
        let shorterDuration = min(
            max(firstEnd.timeIntervalSince(first.startedAt), 0),
            max(secondEnd.timeIntervalSince(second.startedAt), 0)
        )
        guard overlap >= min(shorterDuration * 0.5, 5 * 60) else { return false }

        let firstDistance = first.metrics.distanceMeters
        let secondDistance = second.metrics.distanceMeters
        guard firstDistance > 0, secondDistance > 0 else { return true }
        let difference = abs(firstDistance - secondDistance)
        return difference <= max(max(firstDistance, secondDistance) * 0.25, 1_000)
    }

    private static func enriched(
        _ imported: RideSession,
        preserving existing: RideSession
    ) -> RideSession {
        var result = imported
        if imported.points.isEmpty, !existing.points.isEmpty {
            result.points = existing.points
        }
        if imported.weather == nil {
            result.weather = existing.weather
        }

        var metrics = imported.metrics
        if metrics.distanceMeters <= 0 {
            metrics.distanceMeters = existing.metrics.distanceMeters
        }
        if metrics.movingDurationSeconds <= 0 {
            metrics.movingDurationSeconds = existing.metrics.movingDurationSeconds
        }
        if metrics.elapsedDurationSeconds <= 0 {
            metrics.elapsedDurationSeconds = existing.metrics.elapsedDurationSeconds
        }
        if metrics.averageSpeedMetersPerSecond <= 0 {
            metrics.averageSpeedMetersPerSecond = existing.metrics.averageSpeedMetersPerSecond
        }
        if metrics.maxSpeedMetersPerSecond <= 0 {
            metrics.maxSpeedMetersPerSecond = existing.metrics.maxSpeedMetersPerSecond
        }
        if metrics.elevationGainMeters <= 0 {
            metrics.elevationGainMeters = existing.metrics.elevationGainMeters
        }
        if metrics.averageHeartRate == nil {
            metrics.averageHeartRate = existing.metrics.averageHeartRate
        }
        if metrics.maxHeartRate == nil {
            metrics.maxHeartRate = existing.metrics.maxHeartRate
        }
        if metrics.activeEnergyKilocalories == nil {
            metrics.activeEnergyKilocalories = existing.metrics.activeEnergyKilocalories
        }
        if metrics.totalEnergyKilocalories == nil {
            metrics.totalEnergyKilocalories = existing.metrics.totalEnergyKilocalories
        }
        if metrics.averageCadenceRPM == nil {
            metrics.averageCadenceRPM = existing.metrics.averageCadenceRPM
        }
        if metrics.maxCadenceRPM == nil {
            metrics.maxCadenceRPM = existing.metrics.maxCadenceRPM
        }
        if metrics.averageCyclingPowerWatts == nil {
            metrics.averageCyclingPowerWatts = existing.metrics.averageCyclingPowerWatts
        }
        if metrics.maxCyclingPowerWatts == nil {
            metrics.maxCyclingPowerWatts = existing.metrics.maxCyclingPowerWatts
        }
        result.metrics = metrics
        return result
    }
}
