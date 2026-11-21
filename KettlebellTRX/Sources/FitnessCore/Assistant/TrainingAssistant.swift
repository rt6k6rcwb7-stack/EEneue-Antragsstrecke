import Foundation

/// Empfehlung vor einer Trainingseinheit. Die Kategorien sind nach Vorsicht geordnet.
public enum RecommendationKind: Int, Codable, Sendable, Comparable, CaseIterable {
    case asPlanned = 0
    case adjustReps = 1          // Wiederholungen moderat reduzieren
    case reduceIntensity = 2     // Intensität moderat reduzieren
    case mobilityInstead = 3     // Mobilität statt Krafttraining
    case extraRecovery = 4       // zusätzliche Regeneration (Ruhetag)
    case noTrainingSeeDoctor = 5 // kein Training, ärztliche Abklärung empfohlen

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    public var displayName: String {
        switch self {
        case .asPlanned: return "Training wie geplant"
        case .adjustReps: return "Wiederholungen etwas reduzieren"
        case .reduceIntensity: return "Intensität moderat reduzieren"
        case .mobilityInstead: return "Mobilität statt Krafttraining"
        case .extraRecovery: return "Zusätzliche Regeneration einplanen"
        case .noTrainingSeeDoctor: return "Heute kein Training – ärztliche Abklärung"
        }
    }

    /// Intensitätsfaktor für Sätze/Wiederholungen des Haupttrainings.
    public var intensityFactor: Double {
        switch self {
        case .asPlanned: return 1.0
        case .adjustReps: return 0.9
        case .reduceIntensity: return 0.8
        case .mobilityInstead, .extraRecovery, .noTrainingSeeDoctor: return 0.0
        }
    }
}

/// Eine ausgelöste Regel – macht jede Empfehlung nachvollziehbar.
public struct RuleHit: Codable, Hashable, Sendable, Identifiable {
    public var id: String { ruleId }
    public var ruleId: String
    public var kind: RecommendationKind
    public var message: String
    public var evidence: String
}

public struct Recommendation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var createdAt: Date
    public var kind: RecommendationKind
    public var hits: [RuleHit]
    public var medicalNotice: String?
    /// Fehlende Datenquellen werden ausdrücklich genannt.
    public var missingData: [String]
    /// Ob der Nutzer die Empfehlung übersteuern darf (bei Warnsymptomen nicht innerhalb der App).
    public var userOverrideAllowed: Bool
    public var suggestedDayType: WorkoutDayType?

    public var intensityFactor: Double { kind.intensityFactor }
}

/// Eingaben für den Assistenten.
public struct AssistantContext: Sendable {
    public var now: Date
    public var profile: UserProfile
    public var plannedWorkout: PlannedWorkout?
    public var history: [WorkoutSession]
    public var checkIn: ReadinessCheckIn?
    public var painReports: [PainReport]
    public var vitals: [VitalSample]

    public init(now: Date, profile: UserProfile, plannedWorkout: PlannedWorkout?, history: [WorkoutSession],
                checkIn: ReadinessCheckIn?, painReports: [PainReport], vitals: [VitalSample]) {
        self.now = now; self.profile = profile; self.plannedWorkout = plannedWorkout; self.history = history
        self.checkIn = checkIn; self.painReports = painReports; self.vitals = vitals
    }
}

/// Regelbasierter Trainingsassistent (Version 1). Regeln: Docs/ASSISTANT_RULES.md.
///
/// Grundsätze:
/// * Die strengste ausgelöste Regel bestimmt die Empfehlung.
/// * Gute Vitalwerte (z. B. hoher Recovery Score) heben NIE eine Warnung auf und führen nie
///   allein zu höherer Intensität.
/// * Nach (fieberhafter) Erkrankung wird keine Rückkehr zu intensivem Training empfohlen.
public struct TrainingAssistant: Sendable {
    public var harmonizer: VitalHarmonizer
    public init(harmonizer: VitalHarmonizer = VitalHarmonizer()) { self.harmonizer = harmonizer }

    public static let medicalDisclaimer =
        "Die App ersetzt keine ärztliche Beratung und leitet aus Vitaldaten keine Trainingsfreigabe ab."

    public func recommend(_ c: AssistantContext) -> Recommendation {
        var hits: [RuleHit] = []
        var missing: [String] = []
        var medical: String?
        var overrideAllowed = true
        func hit(_ id: String, _ kind: RecommendationKind, _ msg: String, _ ev: String) {
            hits.append(RuleHit(ruleId: id, kind: kind, message: msg, evidence: ev))
        }
        let cal = harmonizer.calendar

        // ── Sicherheitsregeln (S) ──────────────────────────────
        if let ci = c.checkIn {
            if ci.hasWarningSymptoms {
                hit("S1", .noTrainingSeeDoctor,
                    "Warnsymptome angegeben (z. B. Brustschmerz, Atemnot, Schwindel, Herzstolpern).",
                    "Selbsteinschätzung vor dem Training")
                medical = "Bitte kein Training. Lass die Symptome ärztlich abklären – bei akuten starken Beschwerden den Notruf 112 wählen."
                overrideAllowed = false
            }
            if ci.hasFever {
                hit("S2", .extraRecovery, "Fieber angegeben – Training pausieren.", "Selbsteinschätzung")
                medical = medical ?? "Bei Fieber kein Training. Rückkehr erst nach vollständiger Genesung, idealerweise nach ärztlicher Rücksprache."
                overrideAllowed = false
            } else if ci.hasAcuteIllnessSymptoms {
                hit("S2b", .mobilityInstead, "Akute Infektzeichen – höchstens leichte Mobilität.", "Selbsteinschätzung")
            }
        }
        switch c.profile.programStatus {
        case .paused(let reason, _, _):
            hit("S3", .extraRecovery, "Programm pausiert (\(reason.displayName)).", "Profil")
        case .returning(let reason, let since):
            let days = cal.dateComponents([.day], from: since, to: c.now).day ?? 0
            hit("S4", .reduceIntensity,
                "Wiedereinstieg nach \(reason.displayName) – die App empfiehlt keine Rückkehr zu intensivem Training.",
                "Seit \(days) Tagen im Wiedereinstieg; Aufhebung nur durch dich (ggf. nach ärztlicher Rücksprache)")
            if reason == .feverishIllness {
                medical = medical ?? "Nach fieberhaften Erkrankungen Belastung nur schrittweise steigern und bei Unsicherheit ärztlich abklären."
            }
        case .active: break
        }
        if c.profile.health.hasCardiovascularRestriction {
            hit("S5", .asPlanned, "Kardiovaskuläre Einschränkung hinterlegt: keine automatische Intensitätssteigerung, Pulswarnung aktiv.",
                "Profil → Gesundheit")
        }
        let recentPain = c.painReports.filter { c.now.timeIntervalSince($0.date) < 7 * 86400 }
        if let strong = recentPain.max(by: { $0.intensity < $1.intensity }), strong.intensity >= 7 {
            hit("S6", .mobilityInstead, "Starke Beschwerden (\(strong.intensity)/10) im Bereich \(strong.region.displayName).",
                "Beschwerdeprotokoll der letzten 7 Tage")
            medical = medical ?? "Starke oder anhaltende Schmerzen bitte ärztlich bzw. physiotherapeutisch abklären."
        } else if recentPain.contains(where: { $0.intensity >= 5 }) {
            hit("S6b", .reduceIntensity, "Beschwerden ≥ 5/10 in den letzten 7 Tagen – betroffene Übungen werden ersetzt.", "Beschwerdeprotokoll")
        }
        if let ci = c.checkIn, !ci.currentPainRegions.isEmpty {
            hit("S7", .reduceIntensity, "Aktuelle Beschwerden: \(ci.currentPainRegions.map(\.displayName).joined(separator: ", ")).",
                "Selbsteinschätzung – betroffene Übungen werden ersetzt")
        }

        // ── Belastungsregeln (L) ───────────────────────────────
        let done = c.history.filter { $0.state == .completed }.sorted { $0.startedAt > $1.startedAt }
        if let last = done.first, let plannedType = c.plannedWorkout?.dayType,
           plannedType != .mobility, plannedType != .recovery,
           last.dayType != .mobility, last.dayType != .recovery {
            let hours = c.now.timeIntervalSince(last.endedAt ?? last.startedAt) / 3600
            if hours < 36 {
                hit("L1", .mobilityInstead, "Letzte intensive Einheit vor \(Int(hours)) Stunden.", "Trainingshistorie (Mindestabstand 36 h)")
            }
        }
        let lastRPEs = done.prefix(3).compactMap { $0.feedback?.rpe }
        if lastRPEs.count == 3 {
            let avg = Double(lastRPEs.reduce(0, +)) / 3
            if avg >= 8.5 { hit("L2", .reduceIntensity, String(format: "Hohe Anstrengung zuletzt (Ø RPE %.1f).", avg), "Letzte 3 Einheiten") }
        }
        if let lastFb = done.first?.feedback, lastFb.wellbeing == .exhausted {
            hit("L3", .reduceIntensity, "Nach der letzten Einheit erschöpft.", "Rückmeldung nach dem Training")
        }
        if let ci = c.checkIn {
            if ci.sleepQuality <= 1 || ci.energy <= 1 {
                hit("L4", .reduceIntensity, "Sehr schlechter Schlaf oder sehr wenig Energie.", "Selbsteinschätzung")
            } else if ci.sleepQuality == 2 || ci.energy == 2 {
                hit("L4b", .adjustReps, "Schlaf oder Energie unterdurchschnittlich.", "Selbsteinschätzung")
            }
            if ci.soreness >= 5 { hit("L5", .mobilityInstead, "Starker Muskelkater.", "Selbsteinschätzung") }
            else if ci.soreness == 4 { hit("L5b", .adjustReps, "Deutlicher Muskelkater.", "Selbsteinschätzung") }
        } else {
            missing.append("Selbsteinschätzung vor dem Training")
        }

        // ── Vitaldatenregeln (V) – nur Vergleiche innerhalb derselben Quelle ───
        var vitalFlags = 0
        if let r = harmonizer.comparableReading(.restingHeartRate, on: c.now, in: c.vitals) {
            let d = r.value - r.baseline.mean
            if d >= 7 {
                vitalFlags += 1
                hit("V1", .reduceIntensity, String(format: "Ruhepuls %.0f über Basislinie (+%.0f).", r.value, d),
                    "\(r.baseline.source.displayName), Basislinie aus \(r.baseline.count) Tagen")
            }
        } else { missing.append("Ruhepuls mit persönlicher Basislinie") }

        var hrvFound = false
        for t in [VitalType.hrvRMSSD, .hrvSDNN] {
            guard let r = harmonizer.comparableReading(t, on: c.now, in: c.vitals) else { continue }
            hrvFound = true
            if r.value < r.baseline.median * 0.75 {
                vitalFlags += 1
                hit("V2", .reduceIntensity, String(format: "%@ deutlich unter Basislinie (%.0f vs. %.0f ms).", t.displayName, r.value, r.baseline.median),
                    "\(r.baseline.source.displayName), gleiche Messmethode")
            }
            break
        }
        if !hrvFound { missing.append("HRV-Trend") }

        let todayKey = DayKey.string(for: c.now, calendar: cal)
        if let sleep = harmonizer.resolve(.sleepDuration, dayKey: todayKey, in: c.vitals) {
            if sleep.value < 300 {
                vitalFlags += 1
                hit("V3", .reduceIntensity, String(format: "Kurzer Schlaf (%.1f h).", sleep.value / 60), sleep.source.displayName)
            } else if sleep.value < 360 {
                hit("V3b", .adjustReps, String(format: "Etwas wenig Schlaf (%.1f h).", sleep.value / 60), sleep.source.displayName)
            }
        } else { missing.append("Schlafdauer der letzten Nacht") }

        if let rec = harmonizer.resolve(.recoveryScore, dayKey: todayKey, in: c.vitals) {
            if rec.value < 34 {
                vitalFlags += 1
                hit("V4", .reduceIntensity, String(format: "Niedriger Recovery Score (%.0f %%).", rec.value), rec.source.displayName)
            }
            // Bewusst KEINE Regel, die bei hohem Score die Intensität erhöht (siehe Grundsätze).
        }
        if vitalFlags >= 2 {
            hit("V5", .mobilityInstead, "Mehrere Regenerationsindikatoren gleichzeitig auffällig.", "\(vitalFlags) Vitaldatenregeln ausgelöst")
        }

        let kind = hits.map(\.kind).max() ?? .asPlanned
        var suggested: WorkoutDayType?
        if kind == .mobilityInstead { suggested = .recovery }
        let id = "rec-\(Int(c.now.timeIntervalSince1970))"
        return Recommendation(id: id, createdAt: c.now, kind: kind, hits: hits, medicalNotice: medical,
                              missingData: missing, userOverrideAllowed: overrideAllowed, suggestedDayType: suggested)
    }
}
