import Foundation
import HealthKit
import WatchConnectivity
import Observation
import FitnessCore

/// Workout-Aufzeichnung auf der Apple Watch.
///
/// * `HKWorkoutSession` + `HKLiveWorkoutBuilder` + `HKLiveWorkoutDataSource` erfassen Puls und Energie.
/// * `startMirroringToCompanionDevice()` spiegelt die Sitzung aufs iPhone (watchOS 10).
/// * Pulswerte werden zusätzlich lokal gepuffert; bei Verbindungsverlust läuft die Aufzeichnung
///   unabhängig weiter. Nach dem Ende geht eine Zusammenfassung mit vollständigem Pulsverlauf per
///   `transferUserInfo` (garantierte Zustellung) ans iPhone.
/// * Gespeichert in Apple Health wird nur mit ausdrücklicher Zustimmung (`saveToHealth`), sonst
///   wird das Workout nach dem Abgleich verworfen.
@MainActor
@Observable
final class WatchWorkoutManager: NSObject {
    let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var state: WatchWorkoutState.State = .notStarted
    private(set) var heartRate: Double?
    private(set) var heartRateDate: Date?
    private(set) var startDate: Date?
    private(set) var activeEnergy: Double?
    private(set) var context: WorkoutContextInfo?
    private(set) var isPhoneConnected = false
    private(set) var lastError: String?

    private var series = HeartRateSeries(source: .appleWatch)
    private var outbox = MessageOutbox()
    private var inbox = MessageInbox()
    private var pendingBatch: [HeartRatePoint] = []
    private var saveToHealth = false
    private var sessionId: UUID?

    private let bufferURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("active-workout-buffer.json")

    struct Buffer: Codable { var sessionId: UUID?; var start: Date?; var points: [HeartRatePoint]; var saveToHealth: Bool }

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    // MARK: Berechtigungen

    func requestAuthorization() async {
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do { try await healthStore.requestAuthorization(toShare: share, read: read) }
        catch { lastError = error.localizedDescription }
    }

    // MARK: Start / Wiederherstellung

    func start(configuration: HKWorkoutConfiguration? = nil) async {
        guard session == nil else { return }
        let config = configuration ?? {
            let c = HKWorkoutConfiguration()
            c.activityType = .functionalStrengthTraining
            c.locationType = .indoor
            return c
        }()
        readApplicationContext()
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            attach(session: s, builder: b)
            let now = Date()
            startDate = now
            series = HeartRateSeries(source: .appleWatch)
            persistBuffer()
            s.startActivity(with: now)
            try await b.beginCollection(at: now)
            try? await s.startMirroringToCompanionDevice()
            publishState()
        } catch {
            lastError = "Workout konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    /// Nach Absturz/Neustart der Watch-App: laufende Sitzung übernehmen.
    func recoverIfNeeded() async {
        do {
            guard let s = try await healthStore.recoverActiveWorkoutSession() else { return }
            attach(session: s, builder: s.associatedWorkoutBuilder())
            if let buf = try? JSONDecoder().decode(Buffer.self, from: Data(contentsOf: bufferURL)) {
                series.append(contentsOf: buf.points)
                startDate = buf.start
                sessionId = buf.sessionId
                saveToHealth = buf.saveToHealth
            }
            state = s.state == .paused ? .paused : .running
            try? await s.startMirroringToCompanionDevice()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func attach(session s: HKWorkoutSession, builder b: HKLiveWorkoutBuilder) {
        session = s
        builder = b
        s.delegate = self
        b.delegate = self
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() { session?.end() }

    var elapsed: TimeInterval { builder?.elapsedTime ?? 0 }

    // MARK: Nachrichten

    private func send(_ m: WatchMessage) {
        let env = outbox.enqueue(m, at: Date())
        guard let data = try? env.encoded() else { return }
        if let s = session {
            Task {
                do {
                    try await s.sendToRemoteWorkoutSession(data: data)
                    self.outbox.acknowledge(upTo: env.seq)
                    self.isPhoneConnected = true
                } catch {
                    self.isPhoneConnected = false   // bleibt in der Outbox; Zusammenfassung folgt garantiert
                }
            }
        }
    }

    private func publishState() {
        send(.workoutState(WatchWorkoutState(state: state, startDate: startDate, elapsedSeconds: elapsed, sessionId: sessionId)))
    }

    private func flushHeartRate(force: Bool = false) {
        guard !pendingBatch.isEmpty, force || pendingBatch.count >= 1 else { return }
        let batch = pendingBatch
        pendingBatch = []
        send(.heartRate(batch))
    }

    fileprivate func handleIncoming(_ data: Data) {
        guard let env = try? WatchEnvelope.decode(data), inbox.accept(env) else { return }
        isPhoneConnected = true
        switch env.message {
        case .context(let c): context = c
        case .command(.pause): pause()
        case .command(.resume): resume()
        case .command(.end): end()
        case .command(.discard): saveToHealth = false; end()
        default: break
        }
    }

    private func readApplicationContext() {
        guard WCSession.isSupported() else { return }
        let ctx = WCSession.default.receivedApplicationContext
        saveToHealth = ctx["saveToHealth"] as? Bool ?? false
        sessionId = (ctx["sessionId"] as? String).flatMap(UUID.init(uuidString:))
    }

    private func persistBuffer() {
        let buf = Buffer(sessionId: sessionId, start: startDate, points: series.points, saveToHealth: saveToHealth)
        try? JSONEncoder().encode(buf).write(to: bufferURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    // MARK: Abschluss

    private func finish(at date: Date) async {
        guard let b = builder else { return }
        do {
            try await b.endCollection(at: date)
            var workoutUUID: String?
            if saveToHealth {
                let w = try await b.finishWorkout()
                workoutUUID = w?.uuid.uuidString
            } else {
                b.discardWorkout()
            }
            let energy = b.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let summary = WatchWorkoutSummary(sessionId: sessionId, healthKitWorkoutUUID: workoutUUID, start: startDate ?? date, end: date,
                                              averageHeartRate: series.timeWeightedAverage, maxHeartRate: series.maxBpm,
                                              activeEnergyKcal: energy, savedToHealth: workoutUUID != nil, heartRate: series.points)
            transferGuaranteed(.summary(summary))
        } catch {
            lastError = "Abschluss fehlgeschlagen: \(error.localizedDescription)"
        }
        session = nil
        builder = nil
        try? FileManager.default.removeItem(at: bufferURL)
    }

    /// Garantierte Zustellung (wird von watchOS bis zur nächsten Verbindung zwischengespeichert).
    private func transferGuaranteed(_ m: WatchMessage) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let env = outbox.enqueue(m, at: Date())
        if let data = try? env.encoded() { WCSession.default.transferUserInfo(["envelope": data]) }
    }
}

extension WatchWorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            switch toState {
            case .running: self.state = .running
            case .paused: self.state = .paused
            case .ended: self.state = .ended
            default: break
            }
            self.publishState()
            if toState == .ended { await self.finish(at: date) }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in data.forEach { self.handleIncoming($0) } }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        Task { @MainActor in self.isPhoneConnected = false }
    }
}

extension WatchWorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hrType = HKQuantityType(.heartRate)
        var point: HeartRatePoint?
        if collectedTypes.contains(hrType), let stats = workoutBuilder.statistics(for: hrType),
           let q = stats.mostRecentQuantity() {
            // Zeitstempel der Messung (nicht Empfangszeit); Intervalle sind unregelmäßig.
            let date = stats.mostRecentQuantityDateInterval()?.end ?? Date()
            point = HeartRatePoint(date: date, bpm: q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
        }
        let energy = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let energy { self.activeEnergy = energy }
            guard let p = point, self.series.append(p) else { return }
            self.heartRate = p.bpm
            self.heartRateDate = p.date
            self.pendingBatch.append(p)
            self.flushHeartRate()
            if self.series.points.count % 12 == 0 { self.persistBuffer() }
        }
    }
}

extension WatchWorkoutManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.readApplicationContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.handleIncoming(messageData) }
    }
}
