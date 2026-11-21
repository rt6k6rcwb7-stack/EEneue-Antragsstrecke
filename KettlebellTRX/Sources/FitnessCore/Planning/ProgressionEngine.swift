import Foundation

/// Ein Anpassungsvorschlag. Wird NIE automatisch angewendet – der Nutzer bestätigt ihn.
public struct AdjustmentProposal: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case increaseWeight, decreaseWeight, increaseTarget, decreaseTarget }
    public var id: String { "\(exerciseId)-\(kind.rawValue)-\(fromWeek)" }
    public var exerciseId: String
    public var kind: Kind
    public var fromValue: Double
    public var toValue: Double
    public var fromWeek: Int
    public var reason: String

    public var summary: String {
        func fmt(_ v: Double) -> String { v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v) }
        switch kind {
        case .increaseWeight: return "Gewicht \(fmt(fromValue)) → \(fmt(toValue)) kg"
        case .decreaseWeight: return "Gewicht \(fmt(fromValue)) → \(fmt(toValue)) kg"
        case .increaseTarget: return "Vorgabe \(fmt(fromValue)) → \(fmt(toValue))"
        case .decreaseTarget: return "Vorgabe \(fmt(fromValue)) → \(fmt(toValue))"
        }
    }
}

/// Regelbasierte, konservative Progression (Regeln P1–P4, siehe Docs/ASSISTANT_RULES.md).
public struct ProgressionEngine: Sendable {
    public var maxReps = 15
    public var maxSeconds = 60
    public init() {}

    public func proposals(plan: TrainingPlan, history: [WorkoutSession], profile: UserProfile,
                          library: ExerciseLibrary, currentWeek: Int, painReports: [PainReport] = [],
                          now: Date = Date()) -> [AdjustmentProposal] {
        let increasesBlocked = profile.health.hasCardiovascularRestriction
            || profile.programStatus != .active
            || profile.health.intensityFactor < 1.0
        let selector = WeightSelector(available: profile.kettlebellsKg)
        let completed = history.filter { $0.state == .completed && !$0.isDemo }.sorted { $0.startedAt > $1.startedAt }
        let nextWeek = min(currentWeek + 1, plan.weeks.count)

        // Aktuell geplante Werte je Übung (nächste Woche, Haupttraining)
        var planned: [String: PlannedExercise] = [:]
        for w in plan.weeks where w.index == nextWeek {
            for wo in w.workouts { for e in wo.exercises where e.block == .main && planned[e.exerciseId] == nil { planned[e.exerciseId] = e } }
        }

        var result: [AdjustmentProposal] = []
        for (exId, pe) in planned.sorted(by: { $0.key < $1.key }) {
            guard pe.userModified == false, let exercise = library[exId] else { continue }
            let relevant = completed.filter { s in s.exercises.contains { $0.exerciseId == exId && !$0.sets.isEmpty } }.prefix(2)
            guard relevant.count == 2 else { continue }

            let perf = relevant.map { s -> (met: Bool, ratio: Double, rpe: Int?, fit: PostWorkoutFeedback.WeightFit?, pain: Bool) in
                let ex = s.exercises.first { $0.exerciseId == exId }!
                let achieved = ex.sets.reduce(0) { $0 + $1.achieved }
                let target = max(1, ex.sets.reduce(0) { $0 + $1.target })
                let pain = (s.feedback?.painReports ?? []).contains { exercise.stressedRegions.contains($0.region) && $0.intensity >= 3 }
                return (ex.sets.allSatisfy(\.targetMet) && ex.sets.count >= ex.plannedSets, Double(achieved) / Double(target),
                        s.feedback?.rpe, s.feedback?.weightFit, pain)
            }
            let recentRegionPain = painReports.contains {
                exercise.stressedRegions.contains($0.region) && $0.intensity >= 3 && now.timeIntervalSince($0.date) < 14 * 86400
            }

            // P3/P4: Reduktion bei Überlastungszeichen
            let overloaded = perf.contains { ($0.rpe ?? 0) >= 9 || $0.fit == .tooHeavy || $0.ratio < 0.8 || $0.pain }
            if overloaded {
                if let w = pe.weightKg, let lighter = selector.next(below: w) {
                    result.append(.init(exerciseId: exId, kind: .decreaseWeight, fromValue: w, toValue: lighter, fromWeek: nextWeek,
                                        reason: "In den letzten Einheiten sehr anstrengend, zu schwer oder Wiederholungen deutlich verfehlt."))
                } else if pe.target > 4 {
                    let step = pe.targetKind == .reps ? 2 : 5
                    result.append(.init(exerciseId: exId, kind: .decreaseTarget, fromValue: Double(pe.target), toValue: Double(pe.target - step),
                                        fromWeek: nextWeek, reason: "Belastung zuletzt zu hoch – Vorgabe reduzieren."))
                }
                continue
            }

            // P1/P2: Steigerung nur bei voller Erfüllung, moderater Anstrengung, ohne Beschwerden
            guard !increasesBlocked, !recentRegionPain else { continue }
            let canIncrease = perf.allSatisfy { $0.met && ($0.rpe ?? 10) <= 7 && $0.fit != .tooHeavy && !$0.pain }
            guard canIncrease else { continue }
            let feelsLight = perf.first?.fit == .tooLight
            let atTop = pe.targetKind == .reps ? pe.target >= 12 : pe.target >= 45

            if let w = pe.weightKg, currentWeek >= 4, (feelsLight || atTop), !exercise.isBallistic || profile.health.ballisticTechniqueConfirmed,
               let heavier = selector.next(above: w) {
                result.append(.init(exerciseId: exId, kind: .increaseWeight, fromValue: w, toValue: heavier, fromWeek: nextWeek,
                                    reason: "Zwei Einheiten in Folge alle Vorgaben erfüllt bei RPE ≤ 7 und ohne Beschwerden."))
            } else {
                let cap = pe.targetKind == .reps ? maxReps : maxSeconds
                let step = pe.targetKind == .reps ? 2 : 5
                if pe.target + step <= cap {
                    result.append(.init(exerciseId: exId, kind: .increaseTarget, fromValue: Double(pe.target), toValue: Double(pe.target + step),
                                        fromWeek: nextWeek, reason: "Vorgaben sicher erfüllt – moderate Steigerung der Wiederholungen/Dauer."))
                }
            }
        }
        return result
    }

    /// Wendet einen bestätigten Vorschlag auf alle künftigen Wochen an (manuell geänderte Werte bleiben unangetastet).
    public func apply(_ p: AdjustmentProposal, to plan: inout TrainingPlan) {
        for w in plan.weeks.indices where plan.weeks[w].index >= p.fromWeek {
            for wo in plan.weeks[w].workouts.indices {
                for e in plan.weeks[w].workouts[wo].exercises.indices {
                    var ex = plan.weeks[w].workouts[wo].exercises[e]
                    guard ex.exerciseId == p.exerciseId, ex.block == .main, !ex.userModified,
                          plan.weeks[w].workouts[wo].completedSessionId == nil else { continue }
                    switch p.kind {
                    case .increaseWeight, .decreaseWeight: ex.weightKg = p.toValue
                    case .increaseTarget, .decreaseTarget: ex.target = Int(p.toValue)
                    }
                    ex.note = "Angepasst: \(p.summary)"
                    plan.weeks[w].workouts[wo].exercises[e] = ex
                }
            }
        }
    }
}
