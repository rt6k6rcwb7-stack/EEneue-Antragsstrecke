import Foundation

/// Nachrichten zwischen Apple Watch und iPhone.
///
/// Transportwege (siehe Docs/ARCHITECTURE.md):
/// 1. Workout Mirroring (`HKWorkoutSession.sendToRemoteWorkoutSession`) – primär, latenzarm.
/// 2. WatchConnectivity `transferUserInfo` – garantierte Zustellung nach Verbindungsabbruch.
public enum WatchMessage: Codable, Hashable, Sendable {
    case heartRate([HeartRatePoint])
    case workoutState(WatchWorkoutState)
    case command(WatchCommand)
    case context(WorkoutContextInfo)
    case summary(WatchWorkoutSummary)
    case ack(upTo: Int)
}

public enum WatchCommand: String, Codable, Sendable { case pause, resume, end, discard }

public struct WatchWorkoutState: Codable, Hashable, Sendable {
    public enum State: String, Codable, Sendable { case notStarted, running, paused, ended }
    public var state: State
    public var startDate: Date?
    public var elapsedSeconds: Double
    public var sessionId: UUID?
    public init(state: State, startDate: Date?, elapsedSeconds: Double, sessionId: UUID?) {
        self.state = state; self.startDate = startDate; self.elapsedSeconds = elapsedSeconds; self.sessionId = sessionId
    }
}

/// Anzeige auf der Watch (vom iPhone gesendet).
public struct WorkoutContextInfo: Codable, Hashable, Sendable {
    public var exerciseName: String
    public var setText: String
    public var nextExerciseName: String?
    public var restEndsAt: Date?
    public init(exerciseName: String, setText: String, nextExerciseName: String?, restEndsAt: Date?) {
        self.exerciseName = exerciseName; self.setText = setText; self.nextExerciseName = nextExerciseName; self.restEndsAt = restEndsAt
    }
}

public struct WatchWorkoutSummary: Codable, Hashable, Sendable {
    public var sessionId: UUID?
    public var healthKitWorkoutUUID: String?
    public var start: Date
    public var end: Date
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var activeEnergyKcal: Double?
    public var savedToHealth: Bool
    /// Vollständiger Pulsverlauf (für den Abgleich nach Verbindungsabbruch).
    public var heartRate: [HeartRatePoint]
    public init(sessionId: UUID?, healthKitWorkoutUUID: String?, start: Date, end: Date, averageHeartRate: Double?,
                maxHeartRate: Double?, activeEnergyKcal: Double?, savedToHealth: Bool, heartRate: [HeartRatePoint]) {
        self.sessionId = sessionId; self.healthKitWorkoutUUID = healthKitWorkoutUUID; self.start = start; self.end = end
        self.averageHeartRate = averageHeartRate; self.maxHeartRate = maxHeartRate; self.activeEnergyKcal = activeEnergyKcal
        self.savedToHealth = savedToHealth; self.heartRate = heartRate
    }
}

public struct WatchEnvelope: Codable, Hashable, Sendable {
    public var seq: Int
    public var sentAt: Date
    public var message: WatchMessage

    public func encoded() throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970
        return try e.encode(self)
    }
    public static func decode(_ data: Data) throws -> WatchEnvelope {
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        return try d.decode(WatchEnvelope.self, from: data)
    }
}

/// Persistierbarer Ausgang: Nachrichten bleiben gespeichert, bis die Gegenseite sie bestätigt.
public struct MessageOutbox: Codable, Hashable, Sendable {
    public private(set) var nextSeq: Int = 1
    public private(set) var pending: [WatchEnvelope] = []
    public var maxPending = 5000

    public init() {}

    @discardableResult
    public mutating func enqueue(_ m: WatchMessage, at now: Date) -> WatchEnvelope {
        let env = WatchEnvelope(seq: nextSeq, sentAt: now, message: m)
        nextSeq += 1
        pending.append(env)
        if pending.count > maxPending {
            // Älteste Live-Pulsnachrichten verwerfen – die Zusammenfassung enthält den vollständigen Verlauf.
            if let i = pending.firstIndex(where: { if case .heartRate = $0.message { return true }; return false }) {
                pending.remove(at: i)
            } else { pending.removeFirst() }
        }
        return env
    }

    public mutating func acknowledge(upTo seq: Int) { pending.removeAll { $0.seq <= seq } }
}

/// Eingang mit Duplikaterkennung (Nachrichten können über zwei Wege doppelt ankommen).
public struct MessageInbox: Codable, Hashable, Sendable {
    public private(set) var highestContiguous: Int = 0
    private var seenAbove: Set<Int> = []
    public init() {}

    /// `true`, wenn die Nachricht neu ist und verarbeitet werden soll.
    public mutating func accept(_ env: WatchEnvelope) -> Bool {
        guard env.seq > highestContiguous, !seenAbove.contains(env.seq) else { return false }
        seenAbove.insert(env.seq)
        while seenAbove.contains(highestContiguous + 1) {
            highestContiguous += 1
            seenAbove.remove(highestContiguous)
        }
        return true
    }
}
