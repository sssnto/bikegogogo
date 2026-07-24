import SwiftUI

struct WatchRideView: View {
    @EnvironmentObject private var workoutManager: WatchWorkoutManager
    @EnvironmentObject private var bridge: WatchSessionBridge

    var body: some View {
        VStack(spacing: 10) {
            Grid(horizontalSpacing: 6, verticalSpacing: 8) {
                GridRow {
                    WatchMetric(title: "时长", value: workoutManager.elapsedText)
                    WatchMetric(title: "距离", value: workoutManager.distanceText)
                }

                GridRow {
                    WatchMetric(title: "心率", value: workoutManager.heartRateText)
                    WatchMetric(title: "速度", value: workoutManager.speedText)
                }
            }

            HStack(spacing: 8) {
                Button {
                    handlePrimaryAction()
                } label: {
                    Image(systemName: workoutManager.isRunning ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    workoutManager.endWorkout()
                    bridge.sendRideState("finished")
                } label: {
                    Image(systemName: "stop.fill")
                }
                .disabled(!workoutManager.hasStarted)
            }

            Button {
                bridge.toggleMute()
            } label: {
                Image(systemName: bridge.isMuted ? "mic.slash.fill" : "mic.fill")
            }
            .disabled(!workoutManager.hasStarted)
        }
        .padding(.horizontal, 6)
    }

    private func handlePrimaryAction() {
        if !workoutManager.hasStarted {
            workoutManager.startWorkout()
            bridge.sendRideState("recording")
        } else if workoutManager.isRunning {
            workoutManager.pauseWorkout()
            bridge.sendRideState("paused")
        } else {
            workoutManager.resumeWorkout()
            bridge.sendRideState("recording")
        }
    }
}

private struct WatchMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 42)
    }
}

