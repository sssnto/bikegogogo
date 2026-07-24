import SwiftUI

struct RideHistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List(appState.recentRides) { ride in
                NavigationLink {
                    RideDetailView(ride: ride)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ride.title)
                            .font(.headline)
                        HStack {
                            Text(String(format: "%.2f km", ride.metrics.distanceKilometers))
                            Text(String(format: "%.1f km/h", ride.metrics.averageSpeedKilometersPerHour))
                            if let heartRate = ride.metrics.averageHeartRate {
                                Text("\(heartRate) bpm")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("骑行历史")
        }
    }
}
