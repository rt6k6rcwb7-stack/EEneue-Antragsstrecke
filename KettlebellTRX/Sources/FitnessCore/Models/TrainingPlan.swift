import Foundation

public enum WorkoutDayType: String, Codable, CaseIterable, Sendable {
    case strength        // Montag: Kraft und Muskelstabilität
    case mobility        // Mittwoch: Mobilität, Koordination, Stabilität
    case conditioning    // Freitag: Ganzkörper und Kondition
    case recovery        // vom Assistenten vorgeschlagene Regenerationseinheit

    public var displayName: String {
        switch self {
        case .strength: return "Kraft & Muskelstabilität"
        case .mobility: return "Mobilität, Koordination & Stabilität"
        case .conditioning: return "Ganzkörper & Kondition"
        case .recovery: return "Regeneration & Mobilität"
        }
    }
}

public enum BlockKind: String, Codable, CaseIterable, Sendable {
    case warmup, main, cooldown
    public var displayName: String {
        switch self {
        case .warmup: return "Aufwärmen"
        case .main: return "Haupttraining"
        case .cooldown: return "Cool-down & Mobilität"
        }
    }
}

public enum PlanPhase: String, Codable, CaseIterable, Sendable {
    case technique      // Woche 1–2
    case volume         // Woche 3–4
    case progression    // Woche 5–6
    case individual     // Woche 7–8

    public static func forWeek(_ week: Int) -> PlanPhase {
        switch week {
        case ...2: return .technique
        case 3...4: return .volume
        case 5...6: return .progression
        default: return .individual
        }
    }

    public var displayName: String {
        switch self {
        case .technique: return "Technik & Bewegungsqualität"
        case .volume: return "Volumen & Bewegungskontrolle"
        case .progression: return "Schrittweise Steigerung"
        case .individual: return "Individuelle Progression & Überprüfung"
        }
    }
}

/// Eine geplante Übung innerhalb einer Einheit. Alle Werte sind manuell änderbar.
public struct PlannedExercise: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var exerciseId: String
    public var block: BlockKind
    public var sets: Int
    public var targetKind: TargetKind
    public var target: Int
    public var perSide: Bool
    public var weightKg: Double?
    public var restSeconds: Int
    public var note: String
    /// true, sobald der Nutzer Werte manuell verändert hat – automatische Anpassungen
    /// überschreiben solche Werte nicht ungefragt.
    public var userModified: Bool
    /// Falls aus Sicherheitsgründen ersetzt: ursprüngliche Übung und Grund.
    public var substitutedFrom: String?
    public var substitutionReason: String?

    public init(id: UUID = UUID(), exerciseId: String, block: BlockKind, sets: Int, targetKind: TargetKind, target: Int,
                perSide: Bool = false, weightKg: Double? = nil, restSeconds: Int, note: String = "",
                userModified: Bool = false, substitutedFrom: String? = nil, substitutionReason: String? = nil) {
        self.id = id; self.exerciseId = exerciseId; self.block = block; self.sets = sets
        self.targetKind = targetKind; self.target = target; self.perSide = perSide
        self.weightKg = weightKg; self.restSeconds = restSeconds; self.note = note
        self.userModified = userModified; self.substitutedFrom = substitutedFrom
        self.substitutionReason = substitutionReason
    }
}

public struct PlannedWorkout: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var week: Int            // 1…8
    public var weekday: Weekday
    public var dayType: WorkoutDayType
    public var exercises: [PlannedExercise]
    public var completedSessionId: UUID?

    public init(id: UUID = UUID(), week: Int, weekday: Weekday, dayType: WorkoutDayType, exercises: [PlannedExercise], completedSessionId: UUID? = nil) {
        self.id = id; self.week = week; self.weekday = weekday; self.dayType = dayType
        self.exercises = exercises; self.completedSessionId = completedSessionId
    }

    public func exercises(in block: BlockKind) -> [PlannedExercise] { exercises.filter { $0.block == block } }

    /// Grobe Dauerschätzung in Sekunden (Arbeitszeit + Pausen + Übergänge).
    public func estimatedDurationSeconds(secondsPerRep: Double = 3.5) -> Int {
        exercises.reduce(0) { total, ex in
            let work = ex.targetKind == .reps ? Double(ex.target) * secondsPerRep : Double(ex.target)
            let sides = ex.perSide ? 2.0 : 1.0
            let perSet = work * sides
            let rests = Double(max(0, ex.sets - 1) * ex.restSeconds)
            return total + Int(perSet * Double(ex.sets) + rests + 20)
        }
    }
}

public struct PlanWeek: Codable, Hashable, Sendable {
    public var index: Int
    public var phase: PlanPhase
    public var workouts: [PlannedWorkout]
}

public struct TrainingPlan: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var startDate: Date
    public var weeks: [PlanWeek]
    public var createdAt: Date
    public var cycleNumber: Int

    public init(id: UUID = UUID(), name: String, startDate: Date, weeks: [PlanWeek], createdAt: Date = Date(), cycleNumber: Int = 1) {
        self.id = id; self.name = name; self.startDate = startDate; self.weeks = weeks
        self.createdAt = createdAt; self.cycleNumber = cycleNumber
    }

    public var allWorkouts: [PlannedWorkout] { weeks.flatMap(\.workouts) }

    public func workout(id: UUID) -> PlannedWorkout? { allWorkouts.first { $0.id == id } }

    /// Kalendertermin einer geplanten Einheit.
    public func date(of workout: PlannedWorkout, calendar: Calendar = .iso8601Monday) -> Date {
        let weekStart = calendar.startOfWeek(for: startDate)
        let offset = (workout.week - 1) * 7 + (workout.weekday.rawValue - 1)
        return calendar.date(byAdding: .day, value: offset, to: weekStart) ?? startDate
    }

    /// Nächste noch nicht absolvierte Einheit ab einem Zeitpunkt (heute eingeschlossen).
    public func nextWorkout(from date: Date, calendar: Calendar = .iso8601Monday) -> PlannedWorkout? {
        let today = calendar.startOfDay(for: date)
        return allWorkouts
            .filter { $0.completedSessionId == nil && self.date(of: $0, calendar: calendar) >= today }
            .min { self.date(of: $0, calendar: calendar) < self.date(of: $1, calendar: calendar) }
    }

    public func currentWeekIndex(at date: Date, calendar: Calendar = .iso8601Monday) -> Int {
        let start = calendar.startOfWeek(for: startDate)
        let days = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        return min(max(days / 7 + 1, 1), weeks.count)
    }

    public mutating func updateWorkout(_ workout: PlannedWorkout) {
        for w in weeks.indices {
            if let i = weeks[w].workouts.firstIndex(where: { $0.id == workout.id }) {
                weeks[w].workouts[i] = workout
                return
            }
        }
    }
}

public extension Calendar {
    /// Gregorianischer Kalender mit Montag als Wochenbeginn (unabhängig von der Gerätesprache).
    static var iso8601Monday: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.timeZone = TimeZone.current
        return c
    }

    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps).map { startOfDay(for: $0) } ?? startOfDay(for: date)
    }

    func weekday(of date: Date) -> Weekday {
        // Calendar: Sonntag = 1 … Samstag = 7
        let w = component(.weekday, from: date)
        return Weekday(rawValue: w == 1 ? 7 : w - 1)!
    }
}
