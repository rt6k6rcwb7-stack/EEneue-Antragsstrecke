import Foundation

public enum ExperienceLevel: String, Codable, CaseIterable, Sendable {
    case beginner, intermediate, advanced
    public var displayName: String {
        switch self {
        case .beginner: return "Einsteiger"
        case .intermediate: return "Mittlere Erfahrung"
        case .advanced: return "Fortgeschritten"
        }
    }
}

public enum TrainingGoal: String, Codable, CaseIterable, Sendable {
    case functionalStrength, muscleMaintenance, mobilityCoordination, coreAndBack
    case cardiovascularFitness, golfTennisPerformance, recoveryBalance, healthyAging

    public var displayName: String {
        switch self {
        case .functionalStrength: return "Funktionelle Ganzkörperkraft"
        case .muscleMaintenance: return "Muskulatur langfristig stärken"
        case .mobilityCoordination: return "Beweglichkeit & Koordination"
        case .coreAndBack: return "Rumpfstabilität & Rücken"
        case .cardiovascularFitness: return "Herz-Kreislauf-Fitness"
        case .golfTennisPerformance: return "Leistungsfähigkeit für Golf & Tennis"
        case .recoveryBalance: return "Belastung & Regeneration abstimmen"
        case .healthyAging: return "Gesundes, aktives Altern"
        }
    }
}

public enum Weekday: Int, Codable, CaseIterable, Sendable, Comparable {
    // ISO: Montag = 1
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
    public static func < (a: Weekday, b: Weekday) -> Bool { a.rawValue < b.rawValue }
    public var displayName: String {
        ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"][rawValue - 1]
    }
    public var shortName: String { String(displayName.prefix(2)) }
}

public enum RestrictionSeverity: Int, Codable, CaseIterable, Sendable, Comparable {
    /// Hinweis anzeigen, Übungen bleiben erlaubt.
    case mild = 1
    /// Riskante Bewegungsmuster (Überkopf, ballistisch, Rotation unter Last) für die Region meiden.
    case moderate = 2
    /// Alle Übungen meiden, die diese Region belasten.
    case severe = 3
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var displayName: String {
        switch self {
        case .mild: return "Leicht"
        case .moderate: return "Mittel"
        case .severe: return "Stark"
        }
    }
}

/// Freiwillig erfasste körperliche Einschränkung. Keine Diagnose.
public struct PhysicalRestriction: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var region: BodyRegion
    public var severity: RestrictionSeverity
    public var note: String
    public var since: Date
    public var isActive: Bool

    public init(id: UUID = UUID(), region: BodyRegion, severity: RestrictionSeverity, note: String = "", since: Date = Date(), isActive: Bool = true) {
        self.id = id; self.region = region; self.severity = severity
        self.note = note; self.since = since; self.isActive = isActive
    }
}

/// Dokumentation von Schmerzen/Beschwerden.
public struct PainReport: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var date: Date
    public var region: BodyRegion
    /// 0 = kein Schmerz, 10 = stärkster vorstellbarer Schmerz.
    public var intensity: Int
    public var sessionId: UUID?
    public var exerciseId: String?
    public var note: String

    public init(id: UUID = UUID(), date: Date = Date(), region: BodyRegion, intensity: Int, sessionId: UUID? = nil, exerciseId: String? = nil, note: String = "") {
        self.id = id; self.date = date; self.region = region
        self.intensity = max(0, min(10, intensity))
        self.sessionId = sessionId; self.exerciseId = exerciseId; self.note = note
    }
}

/// Status des Trainingsprogramms (z. B. Pause wegen Erkrankung).
public enum ProgramStatus: Codable, Hashable, Sendable {
    case active
    case paused(reason: PauseReason, since: Date, note: String)
    /// Nach Pause: schonender Wiedereinstieg. Die App hebt diesen Status NIE selbst auf –
    /// nur der Nutzer kann ihn (ggf. nach ärztlicher Abklärung) beenden.
    case returning(after: PauseReason, since: Date)

    public var isPaused: Bool { if case .paused = self { return true }; return false }
}

public enum PauseReason: String, Codable, CaseIterable, Sendable {
    case illness, feverishIllness, injury, travel, other
    public var displayName: String {
        switch self {
        case .illness: return "Erkrankung"
        case .feverishIllness: return "Fieberhafte Erkrankung"
        case .injury: return "Verletzung"
        case .travel: return "Reise"
        case .other: return "Sonstiges"
        }
    }
    /// Gründe, nach denen die App keine Rückkehr zu intensivem Training empfiehlt.
    public var requiresCautiousReturn: Bool { self == .illness || self == .feverishIllness || self == .injury }
}

/// Gesundheitsbezogene Angaben (freiwillig).
public struct HealthSettings: Codable, Hashable, Sendable {
    /// Bekannte kardiovaskuläre Einschränkung: keine automatische Intensitätssteigerung,
    /// keine ballistischen Konditionsblöcke, Pulswarnung aktiv.
    public var hasCardiovascularRestriction: Bool = false
    /// Optionale, vom Nutzer vorgegebene Pulsobergrenze (z. B. ärztliche Vorgabe).
    public var heartRateUpperLimit: Int?
    /// Überkopfbewegungen mit Last grundsätzlich ausschließen.
    public var avoidOverheadLoading: Bool = true
    /// Swing u. ä. erst nach Technikbestätigung.
    public var ballisticTechniqueConfirmed: Bool = false
    /// Globaler Faktor zur Intensitätsreduktion (0,6 … 1,0).
    public var intensityFactor: Double = 1.0

    public init() {}
}

public struct PrivacyConsents: Codable, Hashable, Sendable {
    public var saveWorkoutsToAppleHealth: Bool = false
    public var readAppleHealth: Bool = false
    public var cloudSync: Bool = false            // in V1 nicht implementiert
    public var sendDataToAIServices: Bool = false // in V1 nicht implementiert
    public init() {}
}

public struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var birthYear: Int
    public var heightCm: Double
    public var bodyWeightKg: Double?
    public var experience: ExperienceLevel
    public var kettlebellsKg: [Double]
    public var hasTRX: Bool
    public var sessionsPerWeek: Int
    public var sessionMinutes: ClosedRange<Int>
    public var trainingDays: [Weekday]
    public var sports: [String]
    public var goals: [TrainingGoal]
    public var restrictions: [PhysicalRestriction]
    public var health: HealthSettings
    public var programStatus: ProgramStatus
    public var consents: PrivacyConsents
    public var screening: HealthScreening?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String = "",
        birthYear: Int,
        heightCm: Double,
        bodyWeightKg: Double? = nil,
        experience: ExperienceLevel,
        kettlebellsKg: [Double],
        hasTRX: Bool,
        sessionsPerWeek: Int = 3,
        sessionMinutes: ClosedRange<Int> = 30...40,
        trainingDays: [Weekday] = [.monday, .wednesday, .friday],
        sports: [String] = [],
        goals: [TrainingGoal] = TrainingGoal.allCases,
        restrictions: [PhysicalRestriction] = [],
        health: HealthSettings = HealthSettings(),
        programStatus: ProgramStatus = .active,
        consents: PrivacyConsents = PrivacyConsents(),
        screening: HealthScreening? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id; self.displayName = displayName; self.birthYear = birthYear
        self.heightCm = heightCm; self.bodyWeightKg = bodyWeightKg; self.experience = experience
        self.kettlebellsKg = kettlebellsKg.sorted(); self.hasTRX = hasTRX
        self.sessionsPerWeek = sessionsPerWeek; self.sessionMinutes = sessionMinutes
        self.trainingDays = trainingDays; self.sports = sports; self.goals = goals
        self.restrictions = restrictions; self.health = health
        self.programStatus = programStatus; self.consents = consents; self.screening = screening
        self.updatedAt = updatedAt
    }

    /// Ausgangsprofil laut Auftrag (Vorführmodus und Tests). Alle Werte sind im Profil änderbar.
    public static func initial() -> UserProfile {
        UserProfile(
            birthYear: 1967, heightCm: 193, experience: .intermediate,
            kettlebellsKg: [8, 12, 16], hasTRX: true,
            sports: ["Golf", "Tennis"]
        )
    }

    /// Neutrale Vorbelegung für den Einrichtungsassistenten neuer Familienmitglieder.
    public static func blank(now: Date = Date(), calendar: Calendar = .current) -> UserProfile {
        UserProfile(birthYear: calendar.component(.year, from: now) - 40, heightCm: 175, experience: .beginner,
                    kettlebellsKg: [8, 12], hasTRX: true)
    }

    /// Mindestalter, ab dem das Programm ohne Anleitung vorgesehen ist.
    public static let minimumAge = 16

    public func age(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date) - birthYear
    }

    /// Geschätzte maximale Herzfrequenz nach Tanaka (208 − 0,7 × Alter).
    /// Ausdrücklich eine SCHÄTZUNG – wird in der UI als solche gekennzeichnet.
    public func estimatedMaxHeartRate(on date: Date = Date()) -> Int {
        Int((208.0 - 0.7 * Double(age(on: date))).rounded())
    }

    public var activeRestrictions: [PhysicalRestriction] { restrictions.filter(\.isActive) }
}
