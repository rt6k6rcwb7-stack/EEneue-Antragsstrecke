import Foundation

/// Prüft Übungen gegen Einschränkungen und Gesundheitsangaben des Profils.
/// Konservativ: Im Zweifel wird eine Übung ersetzt, nicht beibehalten.
public struct SafetyFilter: Sendable {
    public struct Verdict: Hashable, Sendable {
        public enum Level: Int, Sendable, Comparable {
            case allowed = 0, caution = 1, excluded = 2
            public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        }
        public var level: Level
        public var reasons: [String]
        public static let allowed = Verdict(level: .allowed, reasons: [])
    }

    public var restrictions: [PhysicalRestriction]
    public var health: HealthSettings
    public var recentPain: [PainReport]
    public var hasTRX: Bool
    public var hasKettlebells: Bool

    public init(profile: UserProfile, recentPain: [PainReport] = []) {
        self.restrictions = profile.activeRestrictions
        self.health = profile.health
        self.recentPain = recentPain
        self.hasTRX = profile.hasTRX
        self.hasKettlebells = !profile.kettlebellsKg.isEmpty
    }

    public func evaluate(_ e: Exercise) -> Verdict {
        var level = Verdict.Level.allowed
        var reasons: [String] = []
        func raise(_ l: Verdict.Level, _ r: String) { level = max(level, l); reasons.append(r) }

        if e.equipment.contains(.trx) && !hasTRX { raise(.excluded, "TRX nicht vorhanden") }
        if e.equipment.contains(.kettlebell) && !hasKettlebells { raise(.excluded, "Keine Kettlebell vorhanden") }

        if e.isOverhead && health.avoidOverheadLoading {
            raise(.excluded, "Überkopfbelastung ist im Profil ausgeschlossen")
        }
        if e.isBallistic {
            if health.hasCardiovascularRestriction {
                raise(.excluded, "Ballistische Übung bei kardiovaskulärer Einschränkung nicht vorgesehen")
            }
            if e.requiresTechniqueCheck && !health.ballisticTechniqueConfirmed {
                raise(.excluded, "Technik noch nicht bestätigt (Profil → Gesundheit)")
            }
        }
        if e.tags.contains(.cardioDemand) && health.hasCardiovascularRestriction && e.isBallistic == false {
            raise(.caution, "Erhöhte Herz-Kreislauf-Belastung – Puls beobachten")
        }

        for r in restrictions where e.stressedRegions.contains(r.region) {
            switch r.severity {
            case .severe:
                raise(.excluded, "Belastet \(r.region.displayName) (starke Einschränkung)")
            case .moderate:
                if e.isOverhead || e.isBallistic || e.tags.contains(.rotation) || e.tags.contains(.loadedSpinalFlexion) {
                    raise(.excluded, "Riskantes Bewegungsmuster für \(r.region.displayName)")
                } else {
                    raise(.caution, "Schonend ausführen: \(r.region.displayName)")
                }
            case .mild:
                raise(.caution, "Hinweis: \(r.region.displayName)")
            }
        }

        // Aktuelle Schmerzen (≥ 5/10) wirken wie eine starke Einschränkung, 3–4 wie eine mittlere.
        for p in recentPain where e.stressedRegions.contains(p.region) {
            if p.intensity >= 5 {
                raise(.excluded, "Aktuelle Beschwerden: \(p.region.displayName) (\(p.intensity)/10)")
            } else if p.intensity >= 3 {
                raise(.caution, "Leichte Beschwerden: \(p.region.displayName)")
            }
        }
        return Verdict(level: level, reasons: reasons)
    }

    /// Sucht die erste sichere Alternative (Regression bevorzugt).
    public func safeSubstitute(for e: Exercise, in library: ExerciseLibrary, excluding: Set<String> = []) -> Exercise? {
        var candidates: [Exercise] = []
        if let r = e.regressionId, let ex = library[r] { candidates.append(ex) }
        candidates += library.alternatives(for: e.id)
        return candidates.first { !excluding.contains($0.id) && evaluate($0).level != .excluded }
    }
}
