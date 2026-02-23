import SwiftUI

// MARK: - Root View

struct ContentView: View {
    @EnvironmentObject var manager: WatchWorkoutManager

    var body: some View {
        switch manager.state {
        case .idle:
            StartView(manager: manager)
        case .running, .paused:
            WorkoutTabView(manager: manager)
        case .ended:
            SummaryView(manager: manager)
        }
    }
}

// MARK: - Start View

/// Full-screen start button, shown before workout begins.
private struct StartView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Omni Runner")
                .font(.headline)

            Spacer()

            if isLoading {
                ProgressView()
                    .tint(.green)
            } else {
                Button {
                    isLoading = true
                    Task {
                        let ok = await manager.requestPermissions()
                        if ok {
                            await manager.startWorkout()
                        }
                        isLoading = false
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Iniciar Corrida")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }
        }
        .padding()
    }
}

// MARK: - Workout Tab View (Paged)

/// Standard watchOS workout pattern: swipe between metric pages.
///
/// - Page 1: Primary metrics (time, HR, distance)
/// - Page 2: Secondary metrics (pace, HR avg/max, GPS count)
/// - Page 3: Controls (pause/resume, end)
private struct WorkoutTabView: View {
    @ObservedObject var manager: WatchWorkoutManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MetricsPage(manager: manager)
                .tag(0)

            DetailPage(manager: manager)
                .tag(1)

            ControlsPage(manager: manager)
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}

// MARK: - Page 1: Primary Metrics

/// The main glance — what the runner sees 90% of the time.
private struct MetricsPage: View {
    @ObservedObject var manager: WatchWorkoutManager

    private var hrZone: HrZone {
        HrZone.zoneFor(bpm: manager.currentHeartRate, maxHr: 190)
    }

    var body: some View {
        VStack(spacing: 4) {
            // Elapsed time — hero metric
            Text(manager.formattedElapsedTime)
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundStyle(.yellow)
                .frame(maxWidth: .infinity, alignment: .center)

            Divider()
                .padding(.horizontal, 8)

            // HR with zone color
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(hrZone.color)
                Text("\(manager.currentHeartRate)")
                    .font(.system(.title, design: .rounded).bold())
                    .foregroundStyle(hrZone.color)
                VStack(alignment: .leading, spacing: 0) {
                    Text("BPM")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(hrZone.shortLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hrZone.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Divider()
                .padding(.horizontal, 8)

            // Distance + Pace side by side
            HStack(spacing: 0) {
                // Distance
                VStack(spacing: 0) {
                    Text(formattedDistanceValue)
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(.green)
                    Text("km")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 1, height: 30)

                // Pace
                VStack(spacing: 0) {
                    Text(manager.formattedPace)
                        .font(.system(.title3, design: .monospaced).bold())
                        .foregroundStyle(.cyan)
                    Text("/km")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // GPS status indicator
            if manager.gpsPoints.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 8))
                    Text("Aguardando GPS")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.orange)
                .padding(.top, 2)
            }

            // Paused overlay
            if manager.state == .paused {
                Text("PAUSADO")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.2))
                    .cornerRadius(4)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDistanceValue: String {
        let km = manager.totalDistanceMeters / 1000.0
        if km >= 10 {
            return String(format: "%.1f", km)
        }
        return String(format: "%.2f", km)
    }
}

// MARK: - Page 2: Detail Metrics

private struct DetailPage: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        VStack(spacing: 6) {
            Text("Detalhes")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            DetailRow(
                icon: "heart.fill",
                label: "FC Média",
                value: "\(manager.averageHeartRate)",
                unit: "BPM",
                color: .red
            )

            DetailRow(
                icon: "heart.circle",
                label: "FC Máx",
                value: "\(manager.maxHeartRate)",
                unit: "BPM",
                color: .orange
            )

            DetailRow(
                icon: "timer",
                label: "Pace",
                value: manager.formattedPace,
                unit: "/km",
                color: .cyan
            )

            DetailRow(
                icon: "location.fill",
                label: "GPS",
                value: "\(manager.gpsPoints.count)",
                unit: "pts",
                color: .green
            )

            DetailRow(
                icon: "waveform.path.ecg",
                label: "HR",
                value: "\(manager.hrSamples.count)",
                unit: "amostras",
                color: .red
            )
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

private struct DetailRow: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced).bold())
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Page 3: Controls

private struct ControlsPage: View {
    @ObservedObject var manager: WatchWorkoutManager
    @State private var showEndConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Pause / Resume
            if manager.state == .running {
                Button {
                    manager.pauseWorkout()
                } label: {
                    HStack {
                        Image(systemName: "pause.fill")
                        Text("Pausar")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .controlSize(.large)
            } else {
                Button {
                    manager.resumeWorkout()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Retomar")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
            }

            // End workout
            Button(role: .destructive) {
                showEndConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Encerrar")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .confirmationDialog(
                "Encerrar corrida?",
                isPresented: $showEndConfirmation,
                titleVisibility: .visible
            ) {
                Button("Encerrar", role: .destructive) {
                    Task { await manager.endWorkout() }
                }
                Button("Cancelar", role: .cancel) {}
            }

            Spacer()
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Summary View

private struct SummaryView: View {
    @ObservedObject var manager: WatchWorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                    Text("Corrida Finalizada")
                        .font(.headline)
                }
                .padding(.top, 4)

                Divider()

                // Primary stats
                HStack(spacing: 0) {
                    SummaryStat(
                        value: manager.formattedElapsedTime,
                        label: "Tempo",
                        color: .yellow
                    )
                    SummaryStat(
                        value: manager.formattedDistance,
                        label: "Distância",
                        color: .green
                    )
                }

                Divider()

                // Secondary stats
                SummaryRow(
                    icon: "timer",
                    label: "Pace médio",
                    value: "\(manager.formattedPace) /km"
                )
                SummaryRow(
                    icon: "heart.fill",
                    label: "FC média",
                    value: "\(manager.averageHeartRate) BPM"
                )
                SummaryRow(
                    icon: "heart.circle",
                    label: "FC máxima",
                    value: "\(manager.maxHeartRate) BPM"
                )
                SummaryRow(
                    icon: "location.fill",
                    label: "GPS points",
                    value: "\(manager.gpsPoints.count)"
                )

                Divider()

                // Restart
                Button {
                    manager.reset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Nova Corrida")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Summary Components

private struct SummaryStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced).bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SummaryRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(WatchWorkoutManager())
}
