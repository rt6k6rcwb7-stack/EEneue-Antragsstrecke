import XCTest
@testable import FitnessCore

final class ExerciseLibraryTests: XCTestCase {
    func testAtLeast40ExercisesWithCompleteFields() {
        let lib = TS.library
        XCTAssertGreaterThanOrEqual(lib.exercises.count, 40)
        XCTAssertEqual(Set(lib.exercises.map(\.id)).count, lib.exercises.count, "IDs müssen eindeutig sein")
        for e in lib.exercises {
            XCTAssertFalse(e.nameDE.isEmpty, e.id)
            XCTAssertFalse(e.summary.isEmpty, e.id)
            XCTAssertFalse(e.startingPosition.isEmpty, e.id)
            XCTAssertFalse(e.movementDirection.isEmpty, e.id)
            XCTAssertFalse(e.breathing.isEmpty, e.id)
            XCTAssertFalse(e.techniqueCues.isEmpty, e.id)
            XCTAssertFalse(e.primaryMuscles.isEmpty, e.id)
            XCTAssertFalse(e.equipment.isEmpty, e.id)
            XCTAssertGreaterThan(e.defaultPrescription.sets, 0, e.id)
            XCTAssertNotNil(PoseLibrary.animation(for: e.animation), "Animation fehlt: \(e.animation) (\(e.id))")
            if e.category != .warmup && e.category != .cooldown && e.id != "mob_chin_tuck" {
                XCTAssertFalse(e.alternatives.isEmpty, "Alternativen fehlen: \(e.id)")
            }
            if e.load.kind == .kettlebell { XCTAssertNotNil(e.load.tier, e.id) }
        }
    }

    func testAllCategoriesPresent() {
        for c in [ExerciseCategory.kettlebell, .trx, .bodyweight, .mobility, .core, .warmup, .cooldown] {
            XCTAssertFalse(TS.library.exercises(in: c).isEmpty, c.rawValue)
        }
    }

    func testReferencesValidAndUserExtensionMerges() throws {
        XCTAssertNoThrow(try TS.library.validate())
        let dir = TS.tempDir()
        var custom = TS.library["bird_dog"]!
        custom.id = "custom_wall_push"
        custom.nameDE = "Eigene Übung"
        let file = ExerciseLibrary.File(schemaVersion: 1, exercises: [custom])
        let url = dir.appendingPathComponent("custom.json")
        try JSONEncoder().encode(file).write(to: url)
        let bundled = Bundle.module.url(forResource: "exercises", withExtension: "json")!
        let merged = try ExerciseLibrary.load(from: [bundled, url])
        XCTAssertEqual(merged.exercises.count, TS.library.exercises.count + 1)
        XCTAssertEqual(merged["custom_wall_push"]?.nameDE, "Eigene Übung")
    }

    func testInvalidReferenceRejected() {
        var e = TS.library["bird_dog"]!
        e.alternatives = ["does_not_exist"]
        XCTAssertThrowsError(try ExerciseLibrary(exercises: [e]).validate())
    }

    func testSearchAndAlternatives() {
        XCTAssertTrue(TS.library.search("goblet").contains { $0.id == "kb_goblet_squat" })
        XCTAssertTrue(TS.library.search("", category: .trx).allSatisfy { $0.category == .trx })
        let alts = TS.library.alternatives(for: "kb_swing").map(\.id)
        XCTAssertEqual(alts.first, "kb_deadlift")
        XCTAssertFalse(alts.contains("kb_swing"))
    }
}

final class PoseTests: XCTestCase {
    func testSkeletonIsGroundedAndInsideFrame() {
        for (id, anim) in PoseLibrary.all {
            for t in stride(from: 0.0, through: anim.cycleSeconds * 2, by: anim.cycleSeconds / 4) {
                let s = PoseRenderer.skeleton(for: anim, at: t)
                let maxY = max(s.joints.values.map(\.y).max()!, s[.head].y + s.headRadius)
                XCTAssertEqual(maxY + anim.pose(at: t).lift, PoseRenderer.floorY, accuracy: 0.0001, id)
                for (j, p) in s.joints {
                    XCTAssertTrue((-0.3...1.3).contains(p.x) && (-0.3...1.0).contains(p.y), "\(id) \(j) außerhalb: \(p)")
                }
            }
        }
    }

    func testPingPongInterpolation() {
        let a = MovementAnimation(id: "t", keyframes: [Pose(torso: 0), Pose(torso: 90)], cycleSeconds: 1)
        XCTAssertEqual(a.pose(at: 0).torso, 0, accuracy: 0.001)
        XCTAssertEqual(a.pose(at: 0.5).torso, 45, accuracy: 0.001)
        XCTAssertEqual(a.pose(at: 1).torso, 90, accuracy: 0.001)
        XCTAssertEqual(a.pose(at: 1.5).torso, 45, accuracy: 0.001)
        XCTAssertEqual(a.pose(at: 2).torso, 0, accuracy: 0.001)
    }
}

final class PlanGeneratorTests: XCTestCase {
    func testEightWeeksThreeDays() {
        let plan = TS.plan()
        XCTAssertEqual(plan.weeks.count, 8)
        for w in plan.weeks {
            XCTAssertEqual(w.workouts.map(\.weekday), [.monday, .wednesday, .friday])
            XCTAssertEqual(w.workouts.map(\.dayType), [.strength, .mobility, .conditioning])
            for wo in w.workouts {
                XCTAssertFalse(wo.exercises(in: .warmup).isEmpty)
                XCTAssertGreaterThanOrEqual(wo.exercises(in: .main).count, 4)
                XCTAssertFalse(wo.exercises(in: .cooldown).isEmpty)
                let minutes = Double(wo.estimatedDurationSeconds()) / 60
                XCTAssertLessThanOrEqual(minutes, 40, "Woche \(w.index) \(wo.dayType)")
                XCTAssertGreaterThanOrEqual(minutes, 20, "Woche \(w.index) \(wo.dayType)")
            }
        }
    }

    func testPhaseProgressionOfSetsRepsAndWeights() {
        let plan = TS.plan()
        func main(_ week: Int, _ id: String) -> PlannedExercise {
            plan.weeks[week - 1].workouts[0].exercises.first { $0.exerciseId == id && $0.block == .main }!
        }
        XCTAssertEqual(main(1, "kb_goblet_squat").sets, 2)
        XCTAssertEqual(main(3, "kb_goblet_squat").sets, 3)
        XCTAssertEqual(main(5, "kb_goblet_squat").target, main(3, "kb_goblet_squat").target + 2)
        XCTAssertEqual(main(8, "kb_goblet_squat").sets, 2, "Woche 8: Überprüfung/Entlastung")
        // Technikphase: eine Stufe leichter
        XCTAssertEqual(main(1, "kb_deadlift").weightKg, 12)
        XCTAssertEqual(main(3, "kb_deadlift").weightKg, 16)
        XCTAssertEqual(main(3, "kb_goblet_squat").weightKg, 12)
        XCTAssertNil(main(3, "trx_row").weightKg)
        let all = plan.allWorkouts.flatMap(\.exercises).compactMap(\.weightKg)
        XCTAssertTrue(Set(all).isSubset(of: [8, 12, 16]))
    }

    func testOverheadNeverPlannedAndSwingRequiresTechniqueConfirmation() {
        let plan = TS.plan()
        let ids = Set(plan.allWorkouts.flatMap(\.exercises).map(\.exerciseId))
        XCTAssertFalse(ids.contains("kb_half_kneeling_press"))
        XCTAssertFalse(ids.contains("kb_swing"), "Swing erst nach Technikbestätigung")
        let friday = plan.weeks[0].workouts[2].exercises.first { $0.substitutedFrom == "kb_swing" }
        XCTAssertEqual(friday?.exerciseId, "kb_deadlift")
        XCTAssertNotNil(friday?.substitutionReason)

        var p = UserProfile.initial()
        p.health.ballisticTechniqueConfirmed = true
        XCTAssertTrue(TS.plan(profile: p).allWorkouts.flatMap(\.exercises).contains { $0.exerciseId == "kb_swing" })

        p.health.hasCardiovascularRestriction = true
        XCTAssertFalse(TS.plan(profile: p).allWorkouts.flatMap(\.exercises).contains { $0.exerciseId == "kb_swing" })
    }

    func testRestrictionsAndPainSubstitute() {
        var p = UserProfile.initial()
        p.restrictions = [PhysicalRestriction(region: .knee, severity: .severe)]
        let plan = TS.plan(profile: p)
        for e in plan.allWorkouts.flatMap(\.exercises) {
            let ex = TS.library[e.exerciseId]!
            XCTAssertFalse(ex.stressedRegions.contains(.knee), "\(ex.id) belastet das Knie")
        }
        let filter = SafetyFilter(profile: .initial(), recentPain: [PainReport(region: .shoulder, intensity: 6)])
        XCTAssertEqual(filter.evaluate(TS.library["trx_chest_press"]!).level, .excluded)
        XCTAssertEqual(filter.evaluate(TS.library["bird_dog"]!).level, .allowed)
    }

    func testNoTRXProfile() {
        var p = UserProfile.initial()
        p.hasTRX = false
        let plan = TS.plan(profile: p)
        XCTAssertFalse(plan.allWorkouts.flatMap(\.exercises).contains { TS.library[$0.exerciseId]!.equipment.contains(.trx) })
    }

    func testDatesAndNextWorkout() {
        let plan = TS.plan()
        let w = plan.weeks[1].workouts[1]
        let d = plan.date(of: w)
        XCTAssertEqual(TS.cal.weekday(of: d), .wednesday)
        XCTAssertEqual(TS.cal.component(.day, from: d), 11)
        XCTAssertEqual(plan.nextWorkout(from: TS.date(3))?.weekday, .wednesday)
        XCTAssertEqual(plan.currentWeekIndex(at: TS.date(12)), 2)
    }

    func testWeightSelector() {
        let s = WeightSelector(available: [16, 8, 12])
        XCTAssertEqual(s.recommended(for: .light), 8)
        XCTAssertEqual(s.recommended(for: .medium), 12)
        XCTAssertEqual(s.recommended(for: .heavy), 16)
        XCTAssertEqual(s.recommended(for: .heavy, experience: .beginner), 12)
        XCTAssertEqual(s.next(above: 12), 16)
        XCTAssertNil(s.next(above: 16))
        XCTAssertEqual(s.next(below: 8), nil)
        XCTAssertNil(WeightSelector(available: []).recommended(for: .medium))
    }
}

final class ProgressionTests: XCTestCase {
    func session(_ plan: TrainingPlan, week: Int, rpe: Int, fit: PostWorkoutFeedback.WeightFit, met: Bool = true, day: Int) -> WorkoutSession {
        let w = plan.weeks[week - 1].workouts[0]
        var run = WorkoutRun.from(planned: w, now: TS.date(day, 18))
        var t = TS.date(day, 18)
        run.start(at: t)
        while case .performing = run.phase {
            t += 30
            run.completeSet(achieved: met ? nil : 1, at: t)
            run.skipRest(at: t)
        }
        run.finish(at: t, feedback: PostWorkoutFeedback(rpe: rpe, weightFit: fit))
        return run.session
    }

    func testIncreaseAfterTwoGoodSessionsAndApply() {
        var plan = TS.plan()
        let hist = [session(plan, week: 4, rpe: 6, fit: .tooLight, day: 23), session(plan, week: 4, rpe: 6, fit: .tooLight, day: 25)]
        let props = ProgressionEngine().proposals(plan: plan, history: hist, profile: .initial(), library: TS.library, currentWeek: 4)
        let gs = props.first { $0.exerciseId == "kb_goblet_squat" }
        XCTAssertEqual(gs?.kind, .increaseWeight)
        XCTAssertEqual(gs?.toValue, 16)
        let trx = props.first { $0.exerciseId == "trx_row" }
        XCTAssertEqual(trx?.kind, .increaseTarget)

        // manuell geänderte Werte bleiben unverändert
        plan.weeks[6].workouts[0].exercises[5].userModified = true
        ProgressionEngine().apply(gs!, to: &plan)
        XCTAssertEqual(plan.weeks[4].workouts[0].exercises.first { $0.exerciseId == "kb_goblet_squat" }?.weightKg, 16)
        XCTAssertEqual(plan.weeks[6].workouts[0].exercises[5].weightKg, 12)
    }

    func testNoIncreaseWithCardioRestrictionOrReturning() {
        let plan = TS.plan()
        let hist = [session(plan, week: 4, rpe: 5, fit: .tooLight, day: 23), session(plan, week: 4, rpe: 5, fit: .tooLight, day: 25)]
        var p = UserProfile.initial()
        p.health.hasCardiovascularRestriction = true
        XCTAssertTrue(ProgressionEngine().proposals(plan: plan, history: hist, profile: p, library: TS.library, currentWeek: 4)
            .allSatisfy { $0.kind == .decreaseWeight || $0.kind == .decreaseTarget })
        p = .initial()
        p.programStatus = .returning(after: .feverishIllness, since: TS.date(20))
        XCTAssertTrue(ProgressionEngine().proposals(plan: plan, history: hist, profile: p, library: TS.library, currentWeek: 4).isEmpty)
    }

    func testDecreaseWhenTooHeavy() {
        let plan = TS.plan()
        let hist = [session(plan, week: 4, rpe: 9, fit: .tooHeavy, day: 23), session(plan, week: 4, rpe: 6, fit: .appropriate, day: 25)]
        let props = ProgressionEngine().proposals(plan: plan, history: hist, profile: .initial(), library: TS.library, currentWeek: 4)
        XCTAssertEqual(props.first { $0.exerciseId == "kb_deadlift" }?.kind, .decreaseWeight)
        XCTAssertEqual(props.first { $0.exerciseId == "kb_deadlift" }?.toValue, 12)
    }
}
