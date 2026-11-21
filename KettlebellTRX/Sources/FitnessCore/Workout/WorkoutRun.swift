import Foundation

/// Laufende Trainingseinheit als reine Zustandsmaschine.
///
/// Alle Operationen erhalten den aktuellen Zeitpunkt als Parameter. Dadurch ist der Player
/// deterministisch testbar und der Zustand kann nach jeder Aktion gespeichert und nach einem
/// App-Neustart oder Verbindungsabbruch exakt wiederhergestellt werden.
public struct WorkoutRun: Codable, Hashable, Sendable {
    public enum Phase: Codable, Hashable, Sendable {
        case notStarted
        case performing
        case resting(until: Date, total: Int)
        case paused(restRemaining: Double?)
        /// Alle Übungen erledigt – wartet auf Abschluss und Feedback.
        case allDone
        case finished
    }

    public private(set) var session: WorkoutSession
    public private(set) var phase: Phase = .notStarted
    public private(set) var exerciseIndex: Int = 0
    public private(set) var activeAccumulated: Double = 0
    public private(set) var activeSince: Date?
    public private(set) var pausedAt: Date?
    public var heartRate: HeartRateSeries
    public private(set) var lastChange: Date
    /// Pause zwischen zwei Übungen (falls die Übung selbst keine vorgibt).
    public var transitionRestSeconds: Int = 20

    public init(session: WorkoutSession, heartRateSource: DataSource? = .appleWatch, now: Date = Date()) {
        self.session = session
        self.heartRate = HeartRateSeries(source: heartRateSource)
        self.lastChange = now
        self.exerciseIndex = session.exercises.firstIndex { !$0.isComplete } ?? 0
    }

    /// Erzeugt eine Einheit aus einer geplanten Trainingseinheit.
    public static func from(planned: PlannedWorkout, intensityFactor: Double = 1.0, now: Date = Date(),
                            recommendationId: String? = nil) -> WorkoutRun {
        let exercises = planned.exercises.map { SessionExercise(planned: $0, intensityFactor: $0.block == .main ? intensityFactor : 1.0) }
        let s = WorkoutSession(plannedWorkoutId: planned.id, dayType: planned.dayType, startedAt: now,
                               exercises: exercises, appliedIntensityFactor: intensityFactor,
                               assistantRecommendationId: recommendationId)
        return WorkoutRun(session: s, now: now)
    }

    // MARK: Abfragen

    public var currentExercise: SessionExercise? {
        session.exercises.indices.contains(exerciseIndex) ? session.exercises[exerciseIndex] : nil
    }
    public var currentSetNumber: Int { (currentExercise?.sets.count ?? 0) + 1 }

    public var nextExercise: SessionExercise? {
        session.exercises.indices.dropFirst(exerciseIndex + 1).first { !session.exercises[$0].isComplete }
            .map { session.exercises[$0] }
    }

    public var isRunning: Bool {
        switch phase { case .performing, .resting: return true; default: return false }
    }
    public var isPaused: Bool { if case .paused = phase { return true }; return false }

    /// Aktive Trainingsdauer ohne Pausen.
    public func elapsed(at now: Date) -> Double {
        activeAccumulated + (activeSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    public func restRemaining(at now: Date) -> Double? {
        switch phase {
        case .resting(let until, _): return max(0, until.timeIntervalSince(now))
        case .paused(let r): return r
        default: return nil
        }
    }

    public var progress: Double {
        let total = session.exercises.reduce(0) { $0 + ($1.skipped ? 0 : $1.plannedSets) }
        let done = session.exercises.reduce(0) { $0 + ($1.skipped ? 0 : min($1.sets.count, $1.plannedSets)) }
        return total == 0 ? 1 : Double(done) / Double(total)
    }

    // MARK: Steuerung

    public mutating func start(at now: Date) {
        guard case .notStarted = phase else { return }
        session.startedAt = now
        session.state = .inProgress
        activeSince = now
        phase = session.exercises.allSatisfy(\.isComplete) ? .allDone : .performing
        lastChange = now
    }

    public mutating func pause(at now: Date) {
        guard isRunning else { return }
        let remaining = restRemaining(at: now)
        accumulate(now)
        pausedAt = now
        phase = .paused(restRemaining: remaining)
        session.state = .paused
        lastChange = now
    }

    public mutating func resume(at now: Date) {
        guard case .paused(let remaining) = phase else { return }
        activeSince = now
        pausedAt = nil
        session.state = .inProgress
        if let r = remaining, r > 0 {
            phase = .resting(until: now.addingTimeInterval(r), total: Int(r.rounded()))
        } else {
            phase = .performing
        }
        lastChange = now
    }

    /// Prüft, ob eine Pause abgelaufen ist, und wechselt dann zur nächsten Aufgabe.
    /// Rückgabe `true`, wenn sich der Zustand geändert hat (z. B. für Haptik/Ton).
    @discardableResult
    public mutating func tick(at now: Date) -> Bool {
        if case .resting(let until, _) = phase, now >= until {
            phase = .performing
            lastChange = now
            return true
        }
        return false
    }

    public mutating func skipRest(at now: Date) {
        guard case .resting = phase else { return }
        phase = .performing
        lastChange = now
    }

    /// Pause verlängern (positiv) oder verkürzen (negativ).
    public mutating func adjustRest(by seconds: Double, at now: Date) {
        switch phase {
        case .resting(let until, let total):
            let newUntil = until.addingTimeInterval(seconds)
            phase = newUntil <= now ? .performing : .resting(until: newUntil, total: max(1, total + Int(seconds)))
        case .paused(let r?):
            phase = .paused(restRemaining: max(0, r + seconds))
        default: return
        }
        lastChange = now
    }

    /// Satz abschließen. `achieved`/`weight` = nil übernimmt die Vorgabe.
    public mutating func completeSet(achieved: Int? = nil, weightKg: Double?? = nil, at now: Date) {
        guard case .performing = phase, var ex = currentExercise else { return }
        let weight: Double? = weightKg ?? ex.weightKg
        let set = ExerciseSet(sessionId: session.id, exerciseId: ex.exerciseId, setIndex: ex.sets.count,
                              targetKind: ex.targetKind, target: ex.target, achieved: max(0, achieved ?? ex.target),
                              perSide: ex.perSide, weightKg: weight, completedAt: now)
        ex.sets.append(set)
        session.exercises[exerciseIndex] = ex
        lastChange = now

        if ex.sets.count < ex.plannedSets {
            startRest(seconds: ex.restSeconds, at: now)
        } else {
            advance(at: now, rest: ex.block == .main ? max(ex.restSeconds, transitionRestSeconds) : 0)
        }
    }

    public mutating func skipExercise(at now: Date) {
        guard var ex = currentExercise, !isFinishedPhase else { return }
        ex.skipped = true
        session.exercises[exerciseIndex] = ex
        lastChange = now
        if isPaused { moveCursorForward(); return }
        advance(at: now, rest: 0)
    }

    /// Ersetzt die aktuelle Übung; bereits absolvierte Sätze bleiben erhalten.
    public mutating func replaceCurrentExercise(with exercise: Exercise, weightKg: Double?, at now: Date) {
        guard var ex = currentExercise else { return }
        if ex.sets.isEmpty {
            ex.replacedExerciseId = ex.replacedExerciseId ?? ex.exerciseId
            ex.exerciseId = exercise.id
            if exercise.defaultPrescription.targetKind != ex.targetKind {
                ex.targetKind = exercise.defaultPrescription.targetKind
                ex.target = exercise.defaultPrescription.target
            }
            ex.perSide = exercise.defaultPrescription.perSide
            ex.weightKg = exercise.load.kind == .kettlebell ? weightKg : nil
            session.exercises[exerciseIndex] = ex
        } else {
            // Teilweise erledigte Übung abschließen und Ersatz mit restlichen Sätzen einfügen.
            let remaining = max(1, ex.plannedSets - ex.sets.count)
            ex.plannedSets = ex.sets.count
            session.exercises[exerciseIndex] = ex
            let replacement = SessionExercise(
                exerciseId: exercise.id, block: ex.block, plannedSets: remaining,
                targetKind: exercise.defaultPrescription.targetKind,
                target: exercise.defaultPrescription.targetKind == ex.targetKind ? ex.target : exercise.defaultPrescription.target,
                perSide: exercise.defaultPrescription.perSide,
                weightKg: exercise.load.kind == .kettlebell ? weightKg : nil, restSeconds: ex.restSeconds,
                replacedExerciseId: ex.exerciseId)
            session.exercises.insert(replacement, at: exerciseIndex + 1)
            exerciseIndex += 1
        }
        lastChange = now
    }

    public mutating func setWeight(_ kg: Double?, at now: Date) {
        guard var ex = currentExercise else { return }
        ex.weightKg = kg
        session.exercises[exerciseIndex] = ex
        lastChange = now
    }

    public mutating func setTarget(_ value: Int, at now: Date) {
        guard var ex = currentExercise else { return }
        ex.target = max(1, value)
        session.exercises[exerciseIndex] = ex
        lastChange = now
    }

    public mutating func setPlannedSets(_ value: Int, at now: Date) {
        guard var ex = currentExercise else { return }
        ex.plannedSets = max(ex.sets.count, max(1, value))
        session.exercises[exerciseIndex] = ex
        lastChange = now
    }

    public mutating func recordHeartRate(_ points: [HeartRatePoint]) {
        heartRate.append(contentsOf: points)
    }

    /// Training beenden (regulär oder vorzeitig). Bereits absolvierte Sätze bleiben gespeichert.
    public mutating func finish(at now: Date, aborted: Bool = false, feedback: PostWorkoutFeedback? = nil) {
        guard !isFinishedPhase || phase == .allDone else { return }
        accumulate(now)
        session.endedAt = now
        session.activeSeconds = activeAccumulated
        session.state = aborted ? .aborted : .completed
        session.heartRate = heartRate.summary
        if let f = feedback { session.feedback = f }
        phase = .finished
        lastChange = now
    }

    public mutating func attachFeedback(_ f: PostWorkoutFeedback) { session.feedback = f }

    // MARK: Intern

    private var isFinishedPhase: Bool {
        switch phase { case .finished, .allDone: return true; default: return false }
    }

    private mutating func accumulate(_ now: Date) {
        if let s = activeSince { activeAccumulated += max(0, now.timeIntervalSince(s)) }
        activeSince = nil
    }

    private mutating func startRest(seconds: Int, at now: Date) {
        phase = seconds > 0 ? .resting(until: now.addingTimeInterval(Double(seconds)), total: seconds) : .performing
    }

    private mutating func moveCursorForward() {
        if let next = session.exercises.indices.dropFirst(exerciseIndex + 1).first(where: { !session.exercises[$0].isComplete }) {
            exerciseIndex = next
        } else if let any = session.exercises.indices.first(where: { !session.exercises[$0].isComplete }) {
            exerciseIndex = any
        }
    }

    private mutating func advance(at now: Date, rest: Int) {
        let before = exerciseIndex
        moveCursorForward()
        if exerciseIndex == before && (currentExercise?.isComplete ?? true) {
            phase = .allDone
            return
        }
        startRest(seconds: rest, at: now)
    }
}
