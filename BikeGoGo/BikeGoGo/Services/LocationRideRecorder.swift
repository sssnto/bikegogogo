import BikeGoGoCore
import Combine
import CoreLocation
import Foundation

final class LocationRideRecorder: NSObject, ObservableObject {
    @Published private(set) var points: [RidePoint] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentSpeedMetersPerSecond = 0.0
    @Published private(set) var lastErrorMessage: String?

    var onPointsChanged: (([RidePoint]) -> Void)?

    private let manager = CLLocationManager()
    private var isRecording = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func requestAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    func start(keepingExistingPoints: Bool = false) {
        if !keepingExistingPoints {
            points.removeAll()
        }
        lastErrorMessage = nil
        isRecording = true
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func pause() {
        isRecording = false
    }

    func resume() {
        isRecording = true
    }

    func stop() {
        isRecording = false
        currentSpeedMetersPerSecond = 0
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func restore(points: [RidePoint]) {
        self.points = points
        currentSpeedMetersPerSecond = points.last?.speedMetersPerSecond ?? 0
    }
}

extension LocationRideRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording else { return }

        let freshnessThreshold = Date().addingTimeInterval(-15)
        let newPoints = locations
            .filter {
                $0.timestamp >= freshnessThreshold
                    && $0.horizontalAccuracy >= 0
                    && $0.horizontalAccuracy <= 50
            }
            .map { location in
                RidePoint(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    elevationMeters: location.altitude,
                    speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
                    courseDegrees: location.course >= 0 ? location.course : nil,
                    horizontalAccuracyMeters: location.horizontalAccuracy,
                    timestamp: location.timestamp
                )
            }

        guard !newPoints.isEmpty else { return }
        points.append(contentsOf: newPoints)
        currentSpeedMetersPerSecond = max(newPoints.last?.speedMetersPerSecond ?? 0, 0)
        onPointsChanged?(points)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        lastErrorMessage = error.localizedDescription
    }
}
