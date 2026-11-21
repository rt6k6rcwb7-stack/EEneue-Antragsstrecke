import Foundation
import HealthKit
import WatchConnectivity
import FitnessCore

/// iPhone-Seite der Watch-Kommunikation.
///
/// Primär: Workout Mirroring (iOS 17 / watchOS 10). Die Watch startet die `HKWorkoutSession`
/// und spiegelt sie aufs iPhone; Pulswerte kommen über `didReceiveDataFromRemoteWorkoutSession`.
/// Ergänzend: WatchConnectivity (`transferUserInfo`) für garantierte Zustellung der
/// Zusammenfassung nach Verbindungsabbrüchen sowie den Applikationskontext (Einwilligungen).
@MainActor
final class WatchWorkoutBridge: NSObject {
    let healthStore: HKHealthStore
    private var mirrored: HKWorkoutSession?
    private var inbox = MessageInbox()
    private var outbox = MessageOutbox()

    var onHeartRate: (([HeartRatePoint]) -> Void)?
    var onSummary: ((WatchWorkoutSummary) -> Void)?
    var onRemoteCommand: ((WatchCommand) -> Void)?
    private(set) var isMirroring = false
    private(set) var lastSessionSavedByWatch = false
    private(set) var lastWatchState: WatchWorkoutState?

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        super.init()
        // Muss früh beim App-Start gesetzt werden, damit gespiegelte Sitzungen ankommen.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in self?.attach(session) }
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func attach(_ session: HKWorkoutSession) {
        mirrored = session
        session.delegate = self
        isMirroring = true
        lastSessionSavedByWatch = false
    }

    /// Startet die Watch-App mit einer Workout-Konfiguration (die Watch übernimmt die Aufzeichnung).
    func startWatchWorkout(sessionId: UUID, saveToHealth: Bool) {
        updateContext(saveToHealth: saveToHealth, pendingSessionId: sessionId)
        guard WCSession.isSupported(), WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor
        healthStore.startWatchApp(with: config) { _, _ in }
    }

    func updateContext(saveToHealth: Bool, pendingSessionId: UUID?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        var ctx: [String: Any] = ["saveToHealth": saveToHealth]
        if let id = pendingSessionId { ctx["sessionId"] = id.uuidString }
        try? WCSession.default.updateApplicationContext(ctx)
    }

    /// Sendet eine Nachricht an die Watch: bevorzugt über die gespiegelte Sitzung, sonst WatchConnectivity.
    func send(_ message: WatchMessage) {
        let env = outbox.enqueue(message, at: Date())
        guard let data = try? env.encoded() else { return }
        if let m = mirrored {
            Task {
                do { try await m.sendToRemoteWorkoutSession(data: data); self.outbox.acknowledge(upTo: env.seq) }
                catch { self.sendViaConnectivity(data) }
            }
        } else {
            sendViaConnectivity(data)
        }
    }

    nonisolated private func sendViaConnectivity(_ data: Data) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessageData(data, replyHandler: nil, errorHandler: nil)
    }

    fileprivate func handle(_ data: Data) {
        guard let env = try? WatchEnvelope.decode(data), inbox.accept(env) else { return }
        switch env.message {
        case .heartRate(let points): onHeartRate?(points)
        case .workoutState(let s): lastWatchState = s
        case .command(let c): onRemoteCommand?(c)
        case .summary(let s):
            lastSessionSavedByWatch = s.savedToHealth
            onSummary?(s)
        case .context, .ack: break
        }
    }
}

extension WatchWorkoutBridge: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        if toState == .ended || toState == .stopped {
            Task { @MainActor in self.isMirroring = false; self.mirrored = nil }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach { self.handle($0) } }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        // Die Watch zeichnet unabhängig weiter auf; Nachlieferung über transferUserInfo (Zusammenfassung).
        Task { @MainActor in self.isMirroring = false }
    }
}

extension WatchWorkoutBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.handle(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["envelope"] as? Data else { return }
        Task { @MainActor in self.handle(data) }
    }
}
