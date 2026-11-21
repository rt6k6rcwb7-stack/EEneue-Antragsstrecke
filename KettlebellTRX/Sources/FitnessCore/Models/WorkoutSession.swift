import Foundation

public struct ExerciseSet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var sessionId: UUID
    public var exerciseId: String
    public var setIndex: Int            // 0-basiert
    public var targetKind: TargetKind
    public var target: Int
    public var achieved: Int            // tatsächliche Wiederholungen / Sekunden
    public var perSide: Bool
    public var weightKg: Double?
    public var completedAt: Date

    public init(id: UUID = UUID(), sessionId: UUID, exerciseId: String, setIndex: Int, targetKind: TargetKind, target: Int,
                achieved: Int, perSide: Bool = false, weightKg: Double?, completedAt: Date) {
        self.id = id; self.sessionId = sessionId; self.exerciseId = exerciseId; self.setIndex = setIndex
        self.targetKind = targetKind; self.target = target; self.achieved = achieved
        self.perSide = perSide; self.weightKg = weightKg; self.completedAt = completedAt
    }

    /// Wiederholungen inkl. beider Seiten (nur bei Wiederholungssätzen).
    public var totalReps: Int { targetKind == .reps ? achieved * (perSide ? 2 : 1) : 0 }
    /// Bewegte Last in kg (nur Kettlebell-Sätze; TRX/Eigengewicht wird bewusst NICHT geschätzt).
    public var tonnageKg: Double { (weightKg ?? 0) * Double(totalReps) }
    public var targetMet: Bool { achieved >= target }
}

public struct SessionExercise: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var plannedExerciseId: UUID?
    public var exerciseId: String
    public var block: BlockKind
    public var plannedSets: Int
    public var targetKind: TargetKind
    public var target: Int
    public var perSide: Bool
    public var weightKg: Double?
    public var restSeconds: Int
    public var sets: [ExerciseSet]
    public var skipped: Bool
    public var replacedExerciseId: String?

    public init(id: UUID = UUID(), plannedExerciseId: UUID? = nil, exerciseId: String, block: BlockKind, plannedSets: Int,
                targetKind: TargetKind, target: Int, perSide: Bool, weightKg: Double?, restSeconds: Int,
                sets: [ExerciseSet] = [], skipped: Bool = false, replacedExerciseId: String? = nil) {
        self.id = id; self.plannedExerciseId = plannedExerciseId; self.exerciseId = exerciseId; self.block = block
        self.plannedSets = plannedSets; self.targetKind = targetKind; self.target = target; self.perSide = perSide
        self.weightKg = weightKg; self.restSeconds = restSeconds; self.sets = sets
        self.skipped = skipped; self.replacedExerciseId = replacedExerciseId
    }

    public init(planned: PlannedExercise, intensityFactor: Double = 1.0) {
        let factor = min(max(intensityFactor, 0.5), 1.0)
        let sets = factor < 0.95 ? max(1, Int((Double(planned.sets) * factor).rounded(.down))) : planned.sets
        self.init(plannedExerciseId: planned.id, exerciseId: planned.exerciseId, block: planned.block,
                  plannedSets: sets, targetKind: planned.targetKind,
                  target: max(1, Int((Double(planned.target) * (factor < 0.95 ? max(factor, 0.8) : 1)).rounded())),
                  perSide: planned.perSide, weightKg: planned.weightKg, restSeconds: planned.restSeconds)
    }

    public var isComplete: Bool { skipped || sets.count >= plannedSets }
}

public enum SessionState: String, Codable, Sendable { case inProgress, paused, completed, aborted }

/// Subjektive Rückmeldung nach dem Training.
public struct PostWorkoutFeedback: Codable, Hashable, Sendable {
    public enum WeightFit: String, Codable, CaseIterable, Sendable {
        case tooLight, appropriate, tooHeavy
        public var displayName: String {
            switch self {
            case .tooLight: return "Zu leicht"
            case .appropriate: return "Angemessen"
            case .tooHeavy: return "Zu schwer"
            }
        }
    }
    public enum Wellbeing: String, Codable, CaseIterable, Sendable {
        case energized, good, tired, exhausted
        public var displayName: String {
            switch self {
            case .energized: return "Energiegeladen"
            case .good: return "Gut"
            case .tired: return "Müde"
            case .exhausted: return "Erschöpft"
            }
        }
    }

    /// Anstrengung 1–10 (Session-RPE).
    public var rpe: Int
    public var hadPain: Bool
    public var painReports: [PainReport]
    public var weightFit: WeightFit
    public var wellbeing: Wellbeing
    public var note: String

    public init(rpe: Int, hadPain: Bool = false, painReports: [PainReport] = [], weightFit: WeightFit = .appropriate, wellbeing: Wellbeing = .good, note: String = "") {
        self.rpe = max(1, min(10, rpe)); self.hadPain = hadPain; self.painReports = painReports
        self.weightFit = weightFit; self.wellbeing = wellbeing; self.note = note
    }
}

/// Zusammenfassung der Herzfrequenz einer Einheit. Fehlende Werte bleiben `nil`.
public struct HeartRateSummary: Codable, Hashable, Sendable {
    public var averageBpm: Double?
    public var maxBpm: Double?
    public var minBpm: Double?
    public var sampleCount: Int
    public var source: DataSource?
    /// Summe der Messlücken > 30 s (z. B. Verbindungsabbruch), in Sekunden.
    public var gapSeconds: Double

    public static let unavailable = HeartRateSummary(averageBpm: nil, maxBpm: nil, minBpm: nil, sampleCount: 0, source: nil, gapSeconds: 0)
}

public struct WorkoutSession: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var plannedWorkoutId: UUID?
    public var dayType: WorkoutDayType
    public var startedAt: Date
    public var endedAt: Date?
    public var activeSeconds: Double
    public var state: SessionState
    public var exercises: [SessionExercise]
    public var feedback: PostWorkoutFeedback?
    public var heartRate: HeartRateSummary
    public var appliedIntensityFactor: Double
    public var assistantRecommendationId: String?
    public var healthKitWorkoutUUID: String?
    public var savedToAppleHealth: Bool
    /// Beispieldaten werden ausdrücklich gekennzeichnet und lassen sich gesammelt löschen.
    public var isDemo: Bool

    public init(id: UUID = UUID(), plannedWorkoutId: UUID?, dayType: WorkoutDayType, startedAt: Date, endedAt: Date? = nil,
                activeSeconds: Double = 0, state: SessionState = .inProgress, exercises: [SessionExercise],
                feedback: PostWorkoutFeedback? = nil, heartRate: HeartRateSummary = .unavailable,
                appliedIntensityFactor: Double = 1.0, assistantRecommendationId: String? = nil,
                healthKitWorkoutUUID: String? = nil, savedToAppleHealth: Bool = false, isDemo: Bool = false) {
        self.id = id; self.plannedWorkoutId = plannedWorkoutId; self.dayType = dayType; self.startedAt = startedAt
        self.endedAt = endedAt; self.activeSeconds = activeSeconds; self.state = state; self.exercises = exercises
        self.feedback = feedback; self.heartRate = heartRate; self.appliedIntensityFactor = appliedIntensityFactor
        self.assistantRecommendationId = assistantRecommendationId; self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.savedToAppleHealth = savedToAppleHealth; self.isDemo = isDemo
    }

    public var allSets: [ExerciseSet] { exercises.flatMap(\.sets) }
    public var totalReps: Int { allSets.reduce(0) { $0 + $1.totalReps } }
    public var tonnageKg: Double { allSets.reduce(0) { $0 + $1.tonnageKg } }
    public var completedSetCount: Int { allSets.count }
    public var isFinished: Bool { state == .completed || state == .aborted }
}

/// Selbsteinschätzung vor dem Training.
public struct ReadinessCheckIn: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    /// 1 = sehr schlecht … 5 = sehr gut
    public var sleepQuality: Int
    public var energy: Int
    /// 1 = kein Muskelkater … 5 = starker Muskelkater
    public var soreness: Int
    public var hasAcuteIllnessSymptoms: Bool   // Erkältung, Infekt
    public var hasFever: Bool
    /// Warnsymptome: Brustschmerz/-enge, Atemnot, Schwindel, Herzstolpern, Ohnmacht.
    public var hasWarningSymptoms: Bool
    public var currentPainRegions: [BodyRegion]

    public init(id: UUID = UUID(), date: Date = Date(), sleepQuality: Int = 3, energy: Int = 3, soreness: Int = 2,
                hasAcuteIllnessSymptoms: Bool = false, hasFever: Bool = false, hasWarningSymptoms: Bool = false,
                currentPainRegions: [BodyRegion] = []) {
        self.id = id; self.date = date; self.sleepQuality = sleepQuality; self.energy = energy; self.soreness = soreness
        self.hasAcuteIllnessSymptoms = hasAcuteIllnessSymptoms; self.hasFever = hasFever
        self.hasWarningSymptoms = hasWarningSymptoms; self.currentPainRegions = currentPainRegions
    }
}
