// Kommandozeilen-Vorschau der Trainingslogik (läuft unter macOS und Linux):
//   swift run kbtrx-plan            → Plan Woche 1–8 (Kurzfassung) und Detail Woche 1
//   swift run kbtrx-plan woche 5    → Detail einer Woche
//   swift run kbtrx-plan simulation → simulierte Einheit inkl. Assistent (BEISPIELDATEN)
import Foundation
import FitnessCore

let lib = try ExerciseLibrary.bundled()
let profile = UserProfile.initial()
let cal = Calendar.iso8601Monday
let start = cal.startOfWeek(for: Date())
let plan = PlanGenerator(library: lib, profile: profile).generate(startDate: start)
let args = CommandLine.arguments.dropFirst()

func name(_ id: String) -> String { lib[id]?.nameDE ?? id }
func line(_ e: PlannedExercise) -> String {
    let t = e.targetKind == .reps ? "\(e.target) Wdh." : "\(e.target) s"
    var s = "  \(e.sets) × \(t)\(e.perSide ? " je Seite" : "")"
    if let w = e.weightKg { s += " @ \(Int(w)) kg" }
    s += "  \(name(e.exerciseId))"
    if let f = e.substitutedFrom { s += "   [ersetzt \(name(f)): \(e.substitutionReason ?? "")]" }
    return s
}
func printWeek(_ w: PlanWeek) {
    print("\n══ Woche \(w.index) – \(w.phase.displayName) ══")
    for wo in w.workouts {
        print("\n\(wo.weekday.displayName) · \(wo.dayType.displayName) · ca. \(wo.estimatedDurationSeconds() / 60) min")
        for b in BlockKind.allCases {
            let items = wo.exercises(in: b)
            guard !items.isEmpty else { continue }
            print(" \(b.displayName):")
            items.forEach { print(line($0)) }
        }
    }
}

if args.first == "woche", let n = args.dropFirst().first.flatMap(Int.init), (1...plan.weeks.count).contains(n) {
    printWeek(plan.weeks[n - 1])
} else if args.first == "simulation" {
    print("SIMULATION MIT BEISPIELDATEN – keine echten Messwerte\n")
    var run = WorkoutRun.from(planned: plan.weeks[0].workouts[0], now: start)
    var t = start
    run.start(at: t)
    var hr = 92.0
    while run.phase != .allDone {
        t += 35
        hr = min(150, hr + 1.5)
        run.recordHeartRate([HeartRatePoint(date: t, bpm: hr)])
        if case .resting = run.phase { t += Double(run.restRemaining(at: t) ?? 0); run.tick(at: t); continue }
        let ex = run.currentExercise!
        print(String(format: "%5.0f s  %@ – Satz %d/%d", run.elapsed(at: t), name(ex.exerciseId), run.currentSetNumber, ex.plannedSets))
        run.completeSet(at: t)
    }
    run.finish(at: t, feedback: PostWorkoutFeedback(rpe: 6))
    let s = run.session
    print(String(format: "\nDauer %.0f min · %d Sätze · %d Wdh. · %.0f kg bewegt · Ø Puls %.0f",
                 s.activeSeconds / 60, s.completedSetCount, s.totalReps, s.tonnageKg, s.heartRate.averageBpm ?? 0))
    let ctx = AssistantContext(now: t + 20 * 3600, profile: profile, plannedWorkout: plan.weeks[0].workouts[1], history: [s],
                               checkIn: ReadinessCheckIn(sleepQuality: 2, energy: 3, soreness: 3), painReports: [], vitals: [])
    let rec = TrainingAssistant().recommend(ctx)
    print("\nAssistent für Mittwoch: \(rec.kind.displayName) (Intensität \(Int(rec.intensityFactor * 100)) %)")
    rec.hits.forEach { print("  \($0.ruleId): \($0.message) – \($0.evidence)") }
    print("  Nicht verfügbar: \(rec.missingData.joined(separator: ", "))")
} else {
    print("Plan „\(plan.name)“ ab \(DayKey.string(for: start)) – \(lib.exercises.count) Übungen in der Bibliothek")
    for w in plan.weeks {
        let mains = w.workouts.map { wo in "\(wo.weekday.shortName) \(wo.exercises(in: .main).first.map { "\($0.sets)×" } ?? "")" }
        print("  Woche \(w.index): \(w.phase.displayName.padding(toLength: 40, withPad: " ", startingAt: 0)) \(mains.joined(separator: "  "))")
    }
    printWeek(plan.weeks[0])
}
