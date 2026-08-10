import BikeGoGoCore
import SwiftUI

struct RideHistoryView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            Group {
                if appState.recentRides.isEmpty,
                   !appState.isSyncingRides,
                   !appState.isImportingHealthKit {
                    ContentUnavailableView {
                        Label("还没有骑行记录", systemImage: "bicycle")
                    } description: {
                        Text("开始一次 BikeGoGo 骑行，或从苹果健身导入已有的户外单车训练。")
                    } actions: {
                        Button("从苹果健身导入") {
                            Task { await appState.refreshRideHistory() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        syncStatus

                        Section("骑行记录") {
                            ForEach(appState.recentRides) { ride in
                                NavigationLink {
                                    RideDetailView(ride: ride)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(ride.title)
                                            .font(.headline)
                                        HStack {
                                            Text(String(
                                                format: "%.2f km",
                                                ride.metrics.distanceKilometers
                                            ))
                                            Text(String(
                                                format: "%.1f km/h",
                                                ride.metrics.averageSpeedKilometersPerHour
                                            ))
                                            if let heartRate = ride.metrics.averageHeartRate {
                                                Text("\(heartRate) bpm")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        Task { await appState.deleteRide(ride) }
                                    }
                                }
                            }
                        }
                    }
                    .refreshable {
                        await appState.refreshRideHistory()
                    }
                }
            }
            .navigationTitle("骑行历史")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.importHealthKitRides() }
                    } label: {
                        Image(systemName: "heart.text.square")
                    }
                    .disabled(appState.isImportingHealthKit)
                    .accessibilityLabel("从苹果健身导入")
                    .help("从苹果健身导入")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.syncRides() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .disabled(
                        appState.isSyncingRides
                            || appState.accountClient.accessToken == nil
                    )
                    .accessibilityLabel("同步骑行记录")
                }
            }
            .overlay {
                if appState.recentRides.isEmpty,
                   appState.isSyncingRides || appState.isImportingHealthKit {
                    ProgressView(
                        appState.isImportingHealthKit
                            ? "正在读取苹果健身"
                            : "正在同步骑行记录"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        if appState.isImportingHealthKit {
            Section {
                Label("正在读取苹果健身", systemImage: "heart.text.square")
                    .foregroundStyle(.secondary)
            }
        } else if let message = appState.healthKitImportMessage {
            Section {
                Label(message, systemImage: "heart.text.square")
                    .foregroundStyle(.secondary)
            }
        } else if appState.isSyncingRides {
            Section {
                Label("正在同步", systemImage: "icloud.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
        } else if let message = appState.rideSyncMessage {
            Section {
                Label(message, systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
        } else if let lastRideSyncAt = appState.lastRideSyncAt {
            Section {
                Label {
                    Text("已同步 \(lastRideSyncAt.formatted(date: .omitted, time: .shortened))")
                } icon: {
                    Image(systemName: "checkmark.icloud")
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
