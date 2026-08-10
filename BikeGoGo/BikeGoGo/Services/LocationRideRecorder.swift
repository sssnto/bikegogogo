import BikeGoGoCore
import Combine
import CoreLocation
import Foundation

final class LocationRideRecorder: NSObject, ObservableObject {
    @Published private(set) var points: [RidePoint] = []
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var currentSpeedMetersPerSecond = 0.0
    @Published private(set) var locationAccuracyMeters: Double?
    @Published private(set) var latestReliablePoint: RidePoint?
    @Published private(set) var isWaitingForAccurateLocation = false
    @Published private(set) var lastErrorMessage: String?

    var onPointsChanged: (([RidePoint]) -> Void)?
    var onReliableLocationChanged: ((RidePoint) -> Void)?
    var onCurrentLocationChanged: ((RidePoint) -> Void)?
    var onMotionChanged: ((Double, Double, Double?, Date) -> Void)?

    private let manager = CLLocationManager()
    private var isRecording = false
    private var isMonitoringForAutoResume = false
    private var isRequestingCurrentLocation = false
    private var locationFilter = RideLocationFilter()

    override init() {
        super.init()
        manager.delegate = self
        configureActiveTracking()
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

    func requestCurrentLocation() {
        isRequestingCurrentLocation = true
        lastErrorMessage = nil
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            configureActiveTracking()
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            isRequestingCurrentLocation = false
        @unknown default:
            isRequestingCurrentLocation = false
        }
    }

    func start(keepingExistingPoints: Bool = false) {
        if !keepingExistingPoints {
            points.removeAll()
        }
        locationFilter.reset(lastAcceptedPoint: keepingExistingPoints ? points.last : nil)
        lastErrorMessage = nil
        locationAccuracyMeters = nil
        latestReliablePoint = nil
        isWaitingForAccurateLocation = true
        isRecording = true
        isMonitoringForAutoResume = false
        configureActiveTracking()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    func pause(keepingMotionUpdates: Bool = false) {
        isRecording = false
        isMonitoringForAutoResume = keepingMotionUpdates
        currentSpeedMetersPerSecond = 0
        if keepingMotionUpdates {
            configureActiveTracking()
            manager.startUpdatingLocation()
        } else {
            manager.stopUpdatingLocation()
        }
    }

    func resume() {
        isRecording = true
        isMonitoringForAutoResume = false
        configureActiveTracking()
        manager.startUpdatingLocation()
    }

    func stop() {
        isRecording = false
        isMonitoringForAutoResume = false
        currentSpeedMetersPerSecond = 0
        locationAccuracyMeters = nil
        latestReliablePoint = nil
        isWaitingForAccurateLocation = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func restore(points: [RidePoint]) {
        self.points = points
        locationFilter.reset(lastAcceptedPoint: points.last)
        currentSpeedMetersPerSecond = points.last?.speedMetersPerSecond ?? 0
    }

    private func configureActiveTracking() {
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }
}

extension LocationRideRecorder: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
        if isRequestingCurrentLocation,
           manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRecording || isMonitoringForAutoResume
                || isRequestingCurrentLocation else { return }

        let freshnessThreshold = Date().addingTimeInterval(-15)
        let freshLocations = locations
            .filter {
                $0.timestamp >= freshnessThreshold
            }

        guard !freshLocations.isEmpty else { return }
        if let latest = freshLocations.last, latest.horizontalAccuracy >= 0 {
            locationAccuracyMeters = latest.horizontalAccuracy
            if latest.horizontalAccuracy
                <= RideLocationFilter.maximumTrackingHorizontalAccuracyMeters {
                currentSpeedMetersPerSecond = max(latest.speed, 0)
            } else {
                currentSpeedMetersPerSecond = 0
            }
            onMotionChanged?(
                max(latest.speed, 0),
                latest.horizontalAccuracy,
                latest.speedAccuracy >= 0 ? latest.speedAccuracy : nil,
                latest.timestamp
            )
        }

        if let reliableLocation = freshLocations.last(where: {
            $0.horizontalAccuracy >= 0
                && $0.horizontalAccuracy
                    <= RideLocationFilter.maximumTrackingHorizontalAccuracyMeters
        }) {
            let point = Self.ridePoint(from: reliableLocation)
            latestReliablePoint = point
            if isRequestingCurrentLocation {
                onCurrentLocationChanged?(point)
            }
            if isRecording {
                onReliableLocationChanged?(point)
            }
            isRequestingCurrentLocation = false
        }

        guard isRecording else { return }

        var newPoints: [RidePoint] = []
        for location in freshLocations {
            let point = Self.ridePoint(from: location)
            if locationFilter.accepts(point) {
                newPoints.append(point)
            }
        }

        guard !newPoints.isEmpty else { return }
        points.append(contentsOf: newPoints)
        isWaitingForAccurateLocation = false
        onPointsChanged?(points)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        isRequestingCurrentLocation = false
        lastErrorMessage = error.localizedDescription
    }

    private static func ridePoint(from location: CLLocation) -> RidePoint {
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
}
