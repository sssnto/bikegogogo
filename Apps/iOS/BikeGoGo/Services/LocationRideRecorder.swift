import BikeGoGoCore
import CoreLocation
import Foundation

final class LocationRideRecorder: NSObject, ObservableObject {
    @Published private(set) var points: [RidePoint] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

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
        manager.requestWhenInUseAuthorization()
        manager.requestAlwaysAuthorization()
    }

    func start() {
        points.removeAll()
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
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }
}

extension LocationRideRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording else { return }

        let newPoints = locations
            .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy <= 50 }
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
        onPointsChanged?(points)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

