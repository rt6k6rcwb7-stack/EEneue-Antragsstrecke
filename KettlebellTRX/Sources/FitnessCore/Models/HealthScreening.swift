import Foundation

/// Kurzes Gesundheits-Screening im Einrichtungsassistenten (angelehnt an gängige
/// Vorab-Fragebögen vor Trainingsbeginn). KEINE Diagnose – bei mindestens einem „Ja“
/// empfiehlt die App eine ärztliche Rücksprache vor Trainingsbeginn.
public struct HealthScreening: Codable, Hashable, Sendable {
    public enum Question: String, Codable, CaseIterable, Sendable {
        case knownHeartCondition, chestPainOnExertion, dizzinessOrFainting
        case bloodPressureOrHeartMedication, jointOrSpineProblem, pregnancy, otherMedicalReason

        public var text: String {
            switch self {
            case .knownHeartCondition: return "Hat eine Ärztin/ein Arzt bei dir eine Herz-Kreislauf-Erkrankung festgestellt oder dir körperliche Belastung nur eingeschränkt erlaubt?"
            case .chestPainOnExertion: return "Hast du bei körperlicher Belastung Schmerzen oder Enge in der Brust?"
            case .dizzinessOrFainting: return "Wird dir manchmal schwindlig oder hast du in den letzten 12 Monaten das Bewusstsein verloren?"
            case .bloodPressureOrHeartMedication: return "Nimmst du Medikamente gegen Bluthochdruck oder für das Herz?"
            case .jointOrSpineProblem: return "Hast du Gelenk-, Knochen- oder Wirbelsäulenprobleme, die sich durch Training verschlechtern könnten?"
            case .pregnancy: return "Bist du schwanger oder hast du vor Kurzem entbunden?"
            case .otherMedicalReason: return "Gibt es einen anderen Grund, aus dem du ohne ärztliche Rücksprache nicht trainieren solltest?"
            }
        }
    }

    public var yes: Set<Question>
    public var answeredAt: Date

    public init(yes: Set<Question> = [], answeredAt: Date = Date()) {
        self.yes = yes; self.answeredAt = answeredAt
    }

    /// Ärztliche Rücksprache vor Trainingsbeginn empfohlen?
    public var recommendsMedicalClearance: Bool { !yes.isEmpty }

    /// Konservative Profileinstellungen aus den Antworten (der Nutzer kann sie später ändern).
    public func apply(to profile: inout UserProfile) {
        let cardiac: Set<Question> = [.knownHeartCondition, .chestPainOnExertion, .dizzinessOrFainting, .bloodPressureOrHeartMedication]
        if !yes.isDisjoint(with: cardiac) {
            profile.health.hasCardiovascularRestriction = true
        }
        if yes.contains(.pregnancy) || yes.contains(.chestPainOnExertion) || yes.contains(.dizzinessOrFainting) {
            profile.health.intensityFactor = min(profile.health.intensityFactor, 0.8)
        }
        profile.health.avoidOverheadLoading = true
        profile.health.ballisticTechniqueConfirmed = false
    }

    public var notices: [String] {
        var n: [String] = []
        if recommendsMedicalClearance {
            n.append("Bitte sprich vor Trainingsbeginn mit deiner Ärztin oder deinem Arzt. Die App leitet keine Trainingsfreigabe ab.")
        }
        if yes.contains(.chestPainOnExertion) || yes.contains(.dizzinessOrFainting) {
            n.append("Brustschmerz oder Schwindel bei Belastung sollten vor jedem Training ärztlich abgeklärt sein.")
        }
        if yes.contains(.pregnancy) {
            n.append("Das Programm ist nicht für Schwangerschaft und Rückbildung ausgelegt – bitte nur nach ärztlicher bzw. hebammenseitiger Rücksprache und mit angepassten Übungen.")
        }
        if yes.contains(.jointOrSpineProblem) {
            n.append("Trage betroffene Bereiche unter „Einschränkungen“ ein – belastende Übungen werden dann ersetzt.")
        }
        return n
    }
}
