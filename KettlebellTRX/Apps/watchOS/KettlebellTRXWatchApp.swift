import SwiftUI
import WatchKit
import HealthKit
import FitnessCore

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    @MainActor static let manager = WatchWorkoutManager()

    /// Wird aufgerufen, wenn das iPhone `startWatchApp(with:)` auslöst.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in await Self.manager.start(configuration: workoutConfiguration) }
    }

    /// Wiederherstellung einer laufenden Sitzung nach Absturz oder Neustart.
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await Self.manager.recoverIfNeeded() }
    }
}

@main
struct KettlebellTRXWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchRootView().environment(WatchAppDelegate.manager)
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var manager

    var body: some View {
        switch manager.state {
        case .notStarted, .ended:
            WatchStartView()
        case .running, .paused:
            TabView {
                WatchSessionView()
                WatchControlsView()
            }
            .tabViewStyle(.verticalPage)
        }
    }
}

struct WatchStartView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.strengthtraining.functional").font(.largeTitle).foregroundStyle(.orange)
            Text("Kettlebell & TRX").font(.headline)
            Text(manager.state == .ended ? "Training beendet – Daten werden übertragen." : "Starte das Training am iPhone oder hier.")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Training starten") { Task { await manager.start() } }
                .tint(.orange)
            if let e = manager.lastError { Text(e).font(.caption2).foregroundStyle(.red) }
        }
        .task { await manager.requestAuthorization() }
    }
}

struct WatchSessionView: View {
    @Environment(WatchWorkoutManager.self) private var manager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                Text(timeText(manager.elapsed))
                    .font(.system(.title2, design: .rounded).monospacedDigit()).foregroundStyle(.yellow)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let hr = manager.heartRate, let d = manager.heartRateDate, ctx.date.timeIntervalSince(d) < 15 {
                        Text("\(Int(hr))").font(.system(size: 44, weight: .semibold, design: .rounded).monospacedDigit())
                        Image(systemName: "heart.fill").foregroundStyle(.red)
                    } else {
                        Text("––").font(.system(size: 44, weight: .semibold, design: .rounded))
                        Text("kein Puls").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let c = manager.context {
                    Text(c.exerciseName).font(.headline).lineLimit(2)
                    if let r = c.restEndsAt, r > ctx.date {
                        Text("Pause \(Int(r.timeIntervalSince(ctx.date))) s").foregroundStyle(.orange)
                    } else {
                        Text(c.setText).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: manager.isPhoneConnected ? "iphone" : "iphone.slash")
                    Text(manager.isPhoneConnected ? "verbunden" : "zeichnet lokal auf")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timeText(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct WatchControlsView: View {
    @Environment(WatchWorkoutManager.self) private var manager
    var body: some View {
        VStack(spacing: 10) {
            Button { manager.state == .paused ? manager.resume() : manager.pause() } label: {
                Label(manager.state == .paused ? "Fortsetzen" : "Pause", systemImage: manager.state == .paused ? "play.fill" : "pause.fill")
            }
            .tint(.yellow)
            Button(role: .destructive) { manager.end() } label: { Label("Beenden", systemImage: "xmark") }
            Text("Satz-Erfassung und Rückmeldung erfolgen am iPhone.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }
}
