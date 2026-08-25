import SwiftUI
import WatchKit

struct WatchRideView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @EnvironmentObject private var bridge: WatchSessionBridge

    @State private var selectedPage = 0
    @State private var showingFinishConfirmation = false

    var body: some View {
        TabView(selection: $selectedPage) {
            primaryMetricsPage.tag(0)
            extendedMetricsPage.tag(1)
            controlsPage.tag(2)
        }
        .tabViewStyle(.verticalPage)
        .alert("骑行提示", isPresented: errorBinding) {
            Button("知道了") {
                workoutManager.dismissError()
            }
        } message: {
            Text(workoutManager.errorMessage ?? "请稍后重试。")
        }
        .confirmationDialog(
            "结束本次骑行？",
            isPresented: $showingFinishConfirmation,
            titleVisibility: .visible
        ) {
            Button("结束并保存", role: .destructive) {
                finishRide()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("骑行数据会保存到 Apple 健康和 BikeGoGo。")
        }
    }

    private var primaryMetricsPage: some View {
        VStack(spacing: 5) {
            statusHeader

            VStack(spacing: 0) {
                Text(workoutManager.speedText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)

                Text("km/h")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("当前速度 \(workoutManager.speedText) 公里每小时")

            HStack(spacing: 4) {
                CompactMetric(
                    title: "时长",
                    value: workoutManager.elapsedText,
                    systemImage: "timer",
                    tint: .yellow
                )
                CompactMetric(
                    title: "距离",
                    value: "\(workoutManager.distanceText) km",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    tint: .green
                )
                CompactMetric(
                    title: "心率",
                    value: "\(workoutManager.heartRateText) bpm",
                    systemImage: "heart.fill",
                    tint: .red
                )
            }
        }
        .padding(.horizontal, 5)
    }

    private var extendedMetricsPage: some View {
        VStack(spacing: 7) {
            HStack {
                Label("更多数据", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                connectionIndicator
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    DetailedMetric(
                        title: "动态能量",
                        value: workoutManager.activeEnergyText,
                        unit: "kcal",
                        systemImage: "flame.fill",
                        tint: .orange
                    )
                    DetailedMetric(
                        title: "累计爬升",
                        value: workoutManager.elevationGainText,
                        unit: "m",
                        systemImage: "mountain.2.fill",
                        tint: .green
                    )
                }
                GridRow {
                    DetailedMetric(
                        title: "踏频",
                        value: workoutManager.cadenceText,
                        unit: "rpm",
                        systemImage: "repeat.circle.fill",
                        tint: .cyan
                    )
                    DetailedMetric(
                        title: "功率",
                        value: workoutManager.powerText,
                        unit: "W",
                        systemImage: "bolt.fill",
                        tint: .yellow
                    )
                }
            }
        }
        .padding(.horizontal, 7)
    }

    private var controlsPage: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("骑行控制")
                        .font(.headline)
                    Text(connectionTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                connectionIndicator
            }

            Button {
                handlePrimaryAction()
            } label: {
                Label(primaryActionTitle, systemImage: primaryActionIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(workoutManager.isRunning ? .orange : .green)

            HStack(spacing: 7) {
                Button {
                    bridge.toggleMute()
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Label(
                        bridge.isMuted ? "已静音" : "麦克风",
                        systemImage: bridge.isMuted ? "mic.slash.fill" : "mic.fill"
                    )
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
                }
                .tint(bridge.isMuted ? .orange : .blue)
                .disabled(!workoutManager.hasStarted)
                .accessibilityLabel(bridge.isMuted ? "取消语音静音" : "将语音静音")

                Button(role: .destructive) {
                    showingFinishConfirmation = true
                } label: {
                    Label("结束", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!workoutManager.hasStarted)
            }

        }
        .padding(.horizontal, 7)
    }

    private var statusHeader: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            Spacer()
            connectionIndicator
        }
    }

    private var connectionIndicator: some View {
        Image(systemName: connectionIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(connectionColor)
            .accessibilityLabel(connectionTitle)
    }

    private var statusTitle: String {
        if workoutManager.isRunning { return "骑行中" }
        if workoutManager.hasStarted { return "已暂停" }
        return "准备骑行"
    }

    private var statusColor: Color {
        if workoutManager.isRunning { return .green }
        if workoutManager.hasStarted { return .orange }
        return .secondary
    }

    private var primaryActionTitle: String {
        if workoutManager.isRunning { return "暂停骑行" }
        if workoutManager.hasStarted { return "继续骑行" }
        return "开始骑行"
    }

    private var primaryActionIcon: String {
        workoutManager.isRunning ? "pause.fill" : "play.fill"
    }

    private var connectionTitle: String {
        if bridge.isPhoneReachable { return "iPhone 已连接" }
        if bridge.isActivated { return "iPhone 后台同步" }
        return "正在连接 iPhone"
    }

    private var connectionIcon: String {
        if bridge.isPhoneReachable { return "iphone.radiowaves.left.and.right" }
        if bridge.isActivated { return "arrow.triangle.2.circlepath" }
        return "iphone.slash"
    }

    private var connectionColor: Color {
        bridge.isPhoneReachable ? .green : (bridge.isActivated ? .cyan : .orange)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { workoutManager.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    workoutManager.dismissError()
                }
            }
        )
    }

    private func handlePrimaryAction() {
        if workoutManager.isRunning {
            workoutManager.pauseWorkout()
            bridge.sendRideState("paused")
            WKInterfaceDevice.current().play(.click)
        } else if workoutManager.hasStarted {
            workoutManager.resumeWorkout()
            bridge.sendRideState("recording")
            WKInterfaceDevice.current().play(.start)
        } else {
            workoutManager.startWorkout()
            bridge.sendRideState("recording")
            WKInterfaceDevice.current().play(.start)
        }
    }

    private func finishRide() {
        workoutManager.endWorkout()
        bridge.sendRideState("finished")
        WKInterfaceDevice.current().play(.stop)
        selectedPage = 0
    }
}

private struct CompactMetric: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct DetailedMetric: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 53, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
