import BikeGoGoCore
import CoreLocation
import MapKit
import SwiftUI

struct RideTrackingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var camera = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
        )
    )

    private var coordinates: [CLLocationCoordinate2D] {
        appState.currentRide.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(position: $camera) {
                    UserAnnotation()

                    if coordinates.count > 1 {
                        MapPolyline(coordinates: coordinates)
                            .stroke(.green, lineWidth: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 340)

                metricsPanel
                    .padding(16)

                controls
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .navigationTitle("BikeGoGo")
            .toolbar {
                Button {
                    appState.requestRidePermissions()
                } label: {
                    Image(systemName: "location.circle")
                }
                .accessibilityLabel("请求定位权限")
            }
        }
    }

    private var metricsPanel: some View {
        let metrics = appState.currentRide.metrics

        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                MetricTile(title: "距离", value: String(format: "%.2f km", metrics.distanceKilometers))
                MetricTile(title: "均速", value: String(format: "%.1f km/h", metrics.averageSpeedKilometersPerHour))
            }

            GridRow {
                MetricTile(title: "最高", value: String(format: "%.1f km/h", metrics.maxSpeedKilometersPerHour))
                MetricTile(title: "爬升", value: String(format: "%.0f m", metrics.elevationGainMeters))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            switch appState.currentRide.state {
            case .idle, .finished:
                Button {
                    appState.startRide()
                } label: {
                    Label("开始骑行", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            case .recording:
                Button {
                    appState.pauseRide()
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(role: .destructive) {
                    appState.finishRide()
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

            case .paused:
                Button {
                    appState.resumeRide()
                } label: {
                    Label("继续", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .destructive) {
                    appState.finishRide()
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

private struct MetricTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

