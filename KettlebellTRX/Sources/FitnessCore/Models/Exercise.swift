import Foundation

// MARK: - Klassifikationen

public enum ExerciseCategory: String, Codable, CaseIterable, Sendable, Hashable {
    case kettlebell, trx, bodyweight, mobility, core, warmup, cooldown

    public var displayName: String {
        switch self {
        case .kettlebell: return "Kettlebell"
        case .trx: return "TRX"
        case .bodyweight: return "Eigengewicht"
        case .mobility: return "Mobilität"
        case .core: return "Core & Stabilität"
        case .warmup: return "Aufwärmen"
        case .cooldown: return "Regeneration"
        }
    }
}

public enum Equipment: String, Codable, CaseIterable, Sendable, Hashable {
    case kettlebell, trx, bodyweight, mat, wall

    public var displayName: String {
        switch self {
        case .kettlebell: return "Kettlebell"
        case .trx: return "TRX"
        case .bodyweight: return "Körpergewicht"
        case .mat: return "Matte"
        case .wall: return "Wand"
        }
    }
}

public enum MuscleGroup: String, Codable, CaseIterable, Sendable, Hashable {
    case quadriceps, hamstrings, glutes, adductors, hipFlexors, calves
    case lowerBack, upperBack, lats, chest, shoulders, rearDelts, rotatorCuff
    case biceps, triceps, forearms, core, obliques, neck, fullBody, cardiovascular

    public var displayName: String {
        switch self {
        case .quadriceps: return "Oberschenkel vorne"
        case .hamstrings: return "Oberschenkel hinten"
        case .glutes: return "Gesäß"
        case .adductors: return "Adduktoren"
        case .hipFlexors: return "Hüftbeuger"
        case .calves: return "Waden"
        case .lowerBack: return "Unterer Rücken"
        case .upperBack: return "Oberer Rücken"
        case .lats: return "Latissimus"
        case .chest: return "Brust"
        case .shoulders: return "Schultern"
        case .rearDelts: return "Hintere Schulter"
        case .rotatorCuff: return "Rotatorenmanschette"
        case .biceps: return "Bizeps"
        case .triceps: return "Trizeps"
        case .forearms: return "Unterarme/Griff"
        case .core: return "Rumpf"
        case .obliques: return "Seitliche Bauchmuskeln"
        case .neck: return "Nacken"
        case .fullBody: return "Ganzkörper"
        case .cardiovascular: return "Herz-Kreislauf"
        }
    }
}

public enum Difficulty: Int, Codable, CaseIterable, Sendable, Comparable {
    case beginner = 1, intermediate = 2, advanced = 3
    public static func < (a: Difficulty, b: Difficulty) -> Bool { a.rawValue < b.rawValue }
    public var displayName: String {
        switch self {
        case .beginner: return "Einsteiger"
        case .intermediate: return "Mittel"
        case .advanced: return "Fortgeschritten"
        }
    }
}

/// Körperregionen, die bei Einschränkungen berücksichtigt werden.
public enum BodyRegion: String, Codable, CaseIterable, Sendable, Hashable {
    case cervicalSpine, thoracicSpine, lumbarSpine, shoulder, elbow, wrist, hip, knee, ankle

    public var displayName: String {
        switch self {
        case .cervicalSpine: return "Halswirbelsäule"
        case .thoracicSpine: return "Brustwirbelsäule"
        case .lumbarSpine: return "Lendenwirbelsäule"
        case .shoulder: return "Schulter"
        case .elbow: return "Ellenbogen"
        case .wrist: return "Handgelenk"
        case .hip: return "Hüfte"
        case .knee: return "Knie"
        case .ankle: return "Sprunggelenk"
        }
    }
}

/// Bewegungsmerkmale, die für Sicherheitsregeln relevant sind.
public enum MovementTag: String, Codable, CaseIterable, Sendable, Hashable {
    case overhead          // Last über Kopf
    case ballistic         // dynamisch-schwunghaft (z. B. Swing)
    case loadedSpinalFlexion
    case rotation
    case hinge, squat, lunge, push, pull, carry, balance, floor, antiRotation, isometric, stretch
    case cardioDemand      // spürbar erhöhte Herz-Kreislauf-Belastung
}

public enum TargetKind: String, Codable, Sendable { case reps, seconds }

/// Standardvorgabe für Sätze/Wiederholungen.
public struct Prescription: Codable, Hashable, Sendable {
    public var sets: Int
    public var targetKind: TargetKind
    public var target: Int            // Wiederholungen bzw. Sekunden
    public var restSeconds: Int
    public var perSide: Bool          // Wiederholungen je Seite

    public init(sets: Int, targetKind: TargetKind = .reps, target: Int, restSeconds: Int, perSide: Bool = false) {
        self.sets = sets; self.targetKind = targetKind; self.target = target
        self.restSeconds = restSeconds; self.perSide = perSide
    }
}

public enum LoadKind: String, Codable, Sendable { case kettlebell, trx, bodyweight, none }

/// Relative Laststufe; wird über `WeightSelector` auf die tatsächlich vorhandenen Kettlebells abgebildet.
public enum LoadTier: String, Codable, Sendable { case light, medium, heavy }

public struct LoadSpec: Codable, Hashable, Sendable {
    public var kind: LoadKind
    public var tier: LoadTier?
    /// Beschreibung für TRX-Winkel / Hebel (z. B. „Körper ca. 45°“).
    public var leverHint: String?

    public init(kind: LoadKind, tier: LoadTier? = nil, leverHint: String? = nil) {
        self.kind = kind; self.tier = tier; self.leverHint = leverHint
    }
}

// MARK: - Übung

/// Eine Übung der Bibliothek. Übungen werden aus `exercises.json` geladen und können
/// ohne Codeänderung ergänzt werden (siehe Docs/EXERCISES.md).
public struct Exercise: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var nameDE: String
    public var nameEN: String?
    public var category: ExerciseCategory
    public var equipment: [Equipment]
    public var primaryMuscles: [MuscleGroup]
    public var secondaryMuscles: [MuscleGroup]
    public var difficulty: Difficulty
    public var summary: String
    public var startingPosition: String
    public var movementDirection: String
    public var breathing: String
    public var techniqueCues: [String]
    public var commonMistakes: [String]
    public var safetyNotes: [String]
    public var stressedRegions: [BodyRegion]
    public var tags: [MovementTag]
    public var load: LoadSpec
    public var defaultPrescription: Prescription
    public var alternatives: [String]
    public var regressionId: String?
    public var progressionId: String?
    /// Kennung einer Bewegungsanimation aus `PoseLibrary`.
    public var animation: String
    /// Optional: Dateiname eines lokal gespeicherten, eigenen bzw. lizenzierten Videos.
    public var mediaFile: String?
    /// Nur nach bestätigter sicherer Technik einsetzen (z. B. Swing).
    public var requiresTechniqueCheck: Bool

    public var isOverhead: Bool { tags.contains(.overhead) }
    public var isBallistic: Bool { tags.contains(.ballistic) }
    public var allMuscles: [MuscleGroup] { primaryMuscles + secondaryMuscles }
}
