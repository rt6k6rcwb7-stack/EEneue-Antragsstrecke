import XCTest
@testable import FitnessCore

final class WorkoutRunTests: XCTestCase {
    func makeRun() -> (WorkoutRun, Date) {
        let w = TS.plan().weeks[2].workouts[0]   // Woche 3, Kraft: 3 Sätze im Haupttraining
        let t0 = TS.date(16, 18)
        return (WorkoutRun.from(planned: w, now: t0), t0)
    }

    func testStartCompleteSetRestAndAdvance() {
        var (run, t) = makeRun()
        XCTAssertEqual(run.phase, .notStarted)
        run.start(at: t)
        XCTAssertEqual(run.phase, .performing)
        XCTAssertEqual(run.currentExercise?.exerciseId, "warm_march")
        // Aufwärmen: 1 Satz, keine Pause → direkt weiter
        run.completeSet(at: t + 60)
        XCTAssertEqual(run.phase, .performing)
        XCTAssertEqual(run.currentExercise?.exerciseId, "warm_hip_circles")
        for _ in 0..<4 { t += 30; run.completeSet(at: t) }
        XCTAssertEqual(run.currentExercise?.exerciseId, "kb_goblet_squat")
        XCTAssertEqual(run.currentSetNumber, 1)
        t += 40
        run.completeSet(achieved: 9, weightKg: .some(12), at: t)
        guard case .resting(let until, let total) = run.phase else { return XCTFail("Pause erwartet") }
        XCTAssertEqual(total, 75)
        XCTAssertEqual(until, t + 75)
        XCTAssertEqual(run.restRemaining(at: t + 25)!, 50, accuracy: 0.001)
        XCTAssertFalse(run.tick(at: t + 74))
        XCTAssertTrue(run.tick(at: t + 75))
        XCTAssertEqual(run.phase, .performing)
        XCTAssertEqual(run.currentSetNumber, 2)
        let set = run.currentExercise!.sets[0]
        XCTAssertEqual(set.achieved, 9)
        XCTAssertEqual(set.target, 10)
        XCTAssertEqual(set.weightKg, 12)
        XCTAssertEqual(run.nextExercise?.exerciseId, "kb_deadlift")
    }

    func testPauseDuringRestPreservesRemainingAndElapsedExcludesPause() {
        var (run, t0) = makeRun()
        run.start(at: t0)
        for i in 0..<5 { run.completeSet(at: t0 + Double(i * 10)) }
        run.completeSet(at: t0 + 100)                 // Goblet Satz 1 → 75 s Pause
        run.pause(at: t0 + 130)                       // 45 s Rest verbleiben
        XCTAssertTrue(run.isPaused)
        XCTAssertEqual(run.restRemaining(at: t0 + 500)!, 45, accuracy: 0.001)
        XCTAssertEqual(run.elapsed(at: t0 + 500), 130, accuracy: 0.001)
        run.resume(at: t0 + 1000)
        guard case .resting(let until, _) = run.phase else { return XCTFail() }
        XCTAssertEqual(until, t0 + 1045)
        XCTAssertEqual(run.elapsed(at: t0 + 1010), 140, accuracy: 0.001)
    }

    func testAdjustRestAndSkipRest() {
        var (run, t) = makeRun()
        run.start(at: t)
        for _ in 0..<6 { run.completeSet(at: t) }
        run.adjustRest(by: 15, at: t)
        XCTAssertEqual(run.restRemaining(at: t)!, 90, accuracy: 0.001)
        run.adjustRest(by: -100, at: t)
        XCTAssertEqual(run.phase, .performing, "Verkürzen unter 0 beendet die Pause")
        run.completeSet(at: t + 10)
        run.skipRest(at: t + 11)
        XCTAssertEqual(run.phase, .performing)
    }

    func testSkipReplaceAdjustAndFinishEarly() {
        var (run, t) = makeRun()
        run.start(at: t)
        for _ in 0..<5 { run.completeSet(at: t) }
        XCTAssertEqual(run.currentExercise?.exerciseId, "kb_goblet_squat")
        run.skipExercise(at: t + 1)
        XCTAssertTrue(run.session.exercises[5].skipped)
        if case .resting = run.phase { run.skipRest(at: t + 1) }
        XCTAssertEqual(run.currentExercise?.exerciseId, "kb_deadlift")

        run.completeSet(at: t + 20)
        run.skipRest(at: t + 21)
        run.replaceCurrentExercise(with: TS.library["kb_suitcase_deadlift"]!, weightKg: 12, at: t + 22)
        XCTAssertEqual(run.session.exercises[6].plannedSets, 1, "Bereits erledigter Satz bleibt beim Original")
        XCTAssertEqual(run.currentExercise?.exerciseId, "kb_suitcase_deadlift")
        XCTAssertEqual(run.currentExercise?.plannedSets, 2)
        XCTAssertEqual(run.currentExercise?.replacedExerciseId, "kb_deadlift")
        run.setWeight(8, at: t + 23)
        run.setTarget(6, at: t + 23)
        run.completeSet(at: t + 40)
        XCTAssertEqual(run.currentExercise?.sets.last?.weightKg, 8)
        XCTAssertEqual(run.currentExercise?.sets.last?.achieved, 6)

        run.finish(at: t + 600, aborted: true)
        XCTAssertEqual(run.session.state, .aborted)
        XCTAssertEqual(run.session.completedSetCount, 5 + 1 + 1)
        XCTAssertEqual(run.phase, .finished)
        run.completeSet(at: t + 700)
        XCTAssertEqual(run.session.completedSetCount, 7, "Nach Abschluss keine Änderungen mehr")
    }

    func testFullWorkoutReachesAllDoneAndSummary() {
        var (run, t) = makeRun()
        run.start(at: t)
        var guardCount = 0
        while run.phase != .allDone && guardCount < 500 {
            guardCount += 1
            t += 20
            run.recordHeartRate([HeartRatePoint(date: t, bpm: 100 + Double(guardCount % 20))])
            if case .resting = run.phase { _ = run.tick(at: t + 200); t += 200; continue }
            run.completeSet(at: t)
        }
        XCTAssertEqual(run.phase, .allDone)
        XCTAssertEqual(run.progress, 1, accuracy: 0.0001)
        run.finish(at: t, feedback: PostWorkoutFeedback(rpe: 6))
        XCTAssertEqual(run.session.state, .completed)
        XCTAssertEqual(run.session.feedback?.rpe, 6)
        XCTAssertNotNil(run.session.heartRate.averageBpm)
        XCTAssertGreaterThan(run.session.tonnageKg, 0)
    }

    func testRestoreAfterRestartIsExact() throws {
        var (run, t) = makeRun()
        run.start(at: t)
        for _ in 0..<6 { run.completeSet(at: t) }
        run.recordHeartRate([HeartRatePoint(date: t, bpm: 110)])
        let repo = try AppRepository(store: LocalStore(directory: TS.tempDir()))
        try repo.saveActiveRun(run)
        let reopened = try AppRepository(store: LocalStore(directory: repo.store.directory))
        XCTAssertEqual(reopened.activeRun, run)
        var restored = reopened.activeRun!
        XCTAssertTrue(restored.tick(at: t + 75))
        XCTAssertEqual(restored.currentSetNumber, 2)
    }

    func testIntensityFactorReducesMainBlockOnly() {
        let w = TS.plan().weeks[2].workouts[0]
        let run = WorkoutRun.from(planned: w, intensityFactor: 0.8, now: TS.date(16))
        let goblet = run.session.exercises.first { $0.exerciseId == "kb_goblet_squat" }!
        XCTAssertEqual(goblet.plannedSets, 2)
        XCTAssertEqual(goblet.target, 8)
        XCTAssertEqual(run.session.exercises.first!.target, 60, "Aufwärmen unverändert")
    }
}

final class HeartRateSeriesTests: XCTestCase {
    func testIrregularIntervalsTimeWeighted() {
        var s = HeartRateSeries(source: .appleWatch)
        let t = TS.date(2)
        // 100 bpm für 10 s, dann 160 bpm-Messung erst nach 2 s → Mittel zeitgewichtet, nicht arithmetisch
        s.append(HeartRatePoint(date: t, bpm: 100))
        s.append(HeartRatePoint(date: t + 10, bpm: 100))
        s.append(HeartRatePoint(date: t + 12, bpm: 160))
        let avg = s.timeWeightedAverage!
        XCTAssertEqual(avg, (100 * 10 + 130 * 2) / 12, accuracy: 0.001)
        XCTAssertEqual(s.maxBpm, 160)
    }

    func testGapsOutOfOrderDuplicatesImplausibleAndStale() {
        var s = HeartRateSeries()
        let t = TS.date(2)
        s.append(HeartRatePoint(date: t + 5, bpm: 110))
        s.append(HeartRatePoint(date: t, bpm: 100))          // verspätet eingetroffen
        XCTAssertFalse(s.append(HeartRatePoint(date: t, bpm: 101)), "Duplikat")
        XCTAssertFalse(s.append(HeartRatePoint(date: t + 6, bpm: 300)), "unplausibel")
        s.append(HeartRatePoint(date: t + 125, bpm: 120))     // 120 s Lücke
        XCTAssertEqual(s.points.map(\.bpm), [100, 110, 120])
        XCTAssertEqual(s.gapSeconds, 120, accuracy: 0.001)
        XCTAssertNotNil(s.current(at: t + 130))
        XCTAssertNil(s.current(at: t + 150), "veralteter Wert wird nicht als aktuell angezeigt")
        XCTAssertEqual(HeartRateSeries().summary, .unavailable)
    }

    func testZones() {
        XCTAssertEqual(HeartRateZone.zone(for: 100, maxHR: 168), .z1)
        XCTAssertEqual(HeartRateZone.zone(for: 130, maxHR: 168), .z3)
        XCTAssertEqual(HeartRateZone.zone(for: 160, maxHR: 168), .z5)
        XCTAssertEqual(UserProfile.initial().estimatedMaxHeartRate(on: TS.date(21)), 167)
    }
}
