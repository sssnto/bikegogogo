import BikeGoGoCore
import SwiftUI

struct RideHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsIncompatibleCleanupConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if appState.recentRides.isEmpty,
                   !appState.isSyncingRides,
                   !appState.isImportingHealthKit {
                    ContentUnavailableView {
                        Label("暂无骑行记录", systemImage: "bicycle")
                    } description: {
                        Text("暂无可显示的户外单车训练")
                    } actions: {
                        Button("从苹果健身导入") {
                            Task { await appState.refreshRideHistory() }
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: BikeGoGoStyle.cornerRadius))
                        .tint(BikeGoGoStyle.brand)
                    }
                } else {
                    historyList
                }
            }
            .navigationTitle("记录")
            .toolbar { historyToolbar }
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
            .confirmationDialog(
                "清理不兼容记录？",
                isPresented: $showsIncompatibleCleanupConfirmation,
                titleVisibility: .visible
            ) {
                Button(
                    "删除 \(appState.incompatibleRideIDs.count) 条记录",
                    role: .destructive
                ) {
                    Task { await appState.deleteIncompatibleRides() }
                }
            } message: {
                Text("这些记录将从 BikeGoGo 本地历史中删除，之后也不会再次从苹果健身导入。苹果健康中的原始训练不会被删除。")
            }
        }
    }

    private var historyList: some View {
        List {
            Section {
                RideHistorySummary(rides: appState.recentRides)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            syncStatus

            Section("骑行记录") {
                ForEach(appState.recentRides) { ride in
                    NavigationLink {
                        RideDetailView(ride: ride)
                    } label: {
                        RideHistoryRow(ride: ride)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 12))
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            Task { await appState.deleteRide(ride) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await appState.refreshRideHistory()
        }
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await appState.importHealthKitRides() }
            } label: {
                Image(systemName: "heart.text.square")
            }
            .disabled(appState.isImportingHealthKit)
            .accessibilityLabel("从苹果健身导入")
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

    @ViewBuilder
    private var syncStatus: some View {
        if appState.isImportingHealthKit {
            RideHistoryStatusRow(
                title: "正在读取苹果健身",
                systemImage: "heart.text.square",
                tint: BikeGoGoStyle.warning,
                showsProgress: true
            )
        } else if let message = appState.healthKitImportMessage {
            RideHistoryStatusRow(
                title: message,
                systemImage: "heart.text.square",
                tint: BikeGoGoStyle.brand
            )
        } else if appState.isSyncingRides {
            RideHistoryStatusRow(
                title: "正在同步骑行记录",
                systemImage: "icloud.and.arrow.up",
                tint: BikeGoGoStyle.warning,
                showsProgress: true
            )
        } else if let message = appState.rideSyncMessage {
            RideHistoryStatusRow(
                title: message,
                systemImage: "exclamationmark.icloud",
                tint: BikeGoGoStyle.warning,
                actionTitle: appState.incompatibleRideIDs.isEmpty ? nil : "清理"
            ) {
                showsIncompatibleCleanupConfirmation = true
            }
        } else if let lastRideSyncAt = appState.lastRideSyncAt {
            RideHistoryStatusRow(
                title: "已同步 · \(ChineseDateFormatting.time(lastRideSyncAt))",
                systemImage: "checkmark.icloud",
                tint: BikeGoGoStyle.brand
            )
        }
    }
}

private struct RideHistorySummary: View {
    let rides: [RideSession]

    private var totalDistance: Double {
        rides.reduce(0) { $0 + $1.metrics.distanceKilometers }
    }

    private var totalDuration: TimeInterval {
        rides.reduce(0) { $0 + $1.metrics.movingDurationSeconds }
    }

    var body: some View {
        HStack(spacing: 0) {
            summaryItem(
                title: "总里程",
                value: totalDistance >= 1_000
                    ? String(format: "%.1f", totalDistance / 1_000)
                    : String(format: "%.0f", totalDistance),
                unit: totalDistance >= 1_000 ? "千公里" : "公里"
            )

            Divider().frame(height: 48)

            summaryItem(
                title: "总时长",
                value: String(format: "%.1f", totalDuration / 3_600),
                unit: "小时"
            )

            Divider().frame(height: 48)

            summaryItem(
                title: "骑行",
                value: "\(rides.count)",
                unit: "次"
            )
        }
        .padding(.vertical, 16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))
    }

    private func summaryItem(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(BikeGoGoStyle.brand)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct RideHistoryRow: View {
    let ride: RideSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sourceIcon)
                .font(.headline)
                .foregroundStyle(BikeGoGoStyle.brand)
                .frame(width: 44, height: 44)
                .background(BikeGoGoStyle.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: BikeGoGoStyle.cornerRadius))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ride.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let weather = ride.weather {
                        Label(
                            "\(Int(weather.temperatureCelsius.rounded()))°",
                            systemImage: weather.symbolName
                        )
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Text(ChineseDateFormatting.dateTime(ride.startedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Text(String(format: "%.2f km", ride.metrics.distanceKilometers))
                        .foregroundStyle(BikeGoGoStyle.brand)
                    Text(String(format: "%.1f km/h", ride.metrics.averageSpeedKilometersPerHour))
                    Text(durationText(ride.metrics.movingDurationSeconds))
                    if let heartRate = ride.metrics.averageHeartRate {
                        Label("\(heartRate)", systemImage: "heart.fill")
                            .foregroundStyle(BikeGoGoStyle.danger)
                    }
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceIcon: String {
        switch ride.source {
        case .iPhone: "iphone"
        case .appleWatch: "applewatch"
        case .merged: "arrow.triangle.merge"
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private struct RideHistoryStatusRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    var showsProgress = false
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView().tint(tint)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(tint)
            }
        }
    }
}
