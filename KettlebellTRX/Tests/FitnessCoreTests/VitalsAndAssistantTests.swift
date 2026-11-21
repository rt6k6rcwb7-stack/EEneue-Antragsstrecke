import XCTest
@testable import FitnessCore

final class HarmonizerTests: XCTestCase {
    let h = VitalHarmonizer()

    func testRepeatedSyncCreatesNoDuplicates() {
        var store: [VitalSample] = []
        let batch = (1...5).map { TS.sample(.restingHeartRate, 55, day: $0, source: .whoop, channel: .whoopAPI) }
        XCTAssertEqual(h.ingest(batch, into: &store).inserted, 5)
        // Gleiche Datensätze, neue lokale UUIDs (wie bei erneutem Abruf)
        let again = batch.map { var s = $0; s.id = UUID(); return s }
        let r = h.ingest(again, into: &store)
        XCTAssertEqual(r.inserted, 0)
        XCTAssertEqual(r.duplicates, 5)
        XCTAssertEqual(store.count, 5)
    }

    func testHealthKitCopiesOfDirectSourcesSuppressedAndImplausibleRejected() {
        var p = SourcePriorities.standard
        p.suppressHealthKitCopiesOf = [.whoop]
        let h2 = VitalHarmonizer(priorities: p)
        var store: [VitalSample] = []
        let r = h2.ingest([
            TS.sample(.restingHeartRate, 55, day: 1, source: .whoop, channel: .healthKit),
            TS.sample(.restingHeartRate, 55, day: 1, source: .whoop, channel: .whoopAPI),
            TS.sample(.heartRate, 400, day: 1, source: .appleWatch),
        ], into: &store)
        XCTAssertEqual(r.inserted, 1)
        XCTAssertEqual(r.suppressed, 1)
        XCTAssertEqual(r.rejected, 1)
        XCTAssertEqual(store.first?.channel, .whoopAPI)
    }

    func testPriorityResolutionKeepsSourcesSeparate() {
        let samples = [
            TS.sample(.restingHeartRate, 60, day: 3, source: .appleWatch),
            TS.sample(.restingHeartRate, 54, day: 3, source: .whoop, channel: .whoopAPI),
            TS.sample(.restingHeartRate, 58, day: 3, source: .garmin),
        ]
        let r = h.resolve(.restingHeartRate, dayKey: "2026-11-03", in: samples)!
        XCTAssertEqual(r.source, .whoop, "Regeneration: WHOOP bevorzugt")
        XCTAssertEqual(r.value, 54)
        XCTAssertEqual(r.alternatives[.appleWatch], 60)
        XCTAssertEqual(r.alternatives[.garmin], 58)

        var p = SourcePriorities.standard
        p.disabledSources = [.whoop]
        XCTAssertEqual(VitalHarmonizer(priorities: p).resolve(.restingHeartRate, dayKey: "2026-11-03", in: samples)?.source, .appleWatch)
        p.order[.restingHeartRate] = [.garmin, .whoop]
        p.disabledSources = []
        XCTAssertEqual(VitalHarmonizer(priorities: p).resolve(.restingHeartRate, dayKey: "2026-11-03", in: samples)?.source, .garmin)
    }

    func testHRVMethodsNeverMixed() {
        var samples: [VitalSample] = []
        for d in 1...10 { samples.append(TS.sample(.hrvRMSSD, 45, day: d, source: .whoop, channel: .whoopAPI)) }
        for d in 1...10 { samples.append(TS.sample(.hrvSDNN, 30, day: d, source: .appleWatch)) }
        let rmssd = h.baseline(.hrvRMSSD, source: .whoop, before: TS.date(11), in: samples)!
        XCTAssertEqual(rmssd.mean, 45, accuracy: 0.001)
        XCTAssertNil(h.baseline(.hrvRMSSD, source: .appleWatch, before: TS.date(11), in: samples))
        let sdnn = h.baseline(.hrvSDNN, source: .appleWatch, before: TS.date(11), in: samples)!
        XCTAssertEqual(sdnn.mean, 30, accuracy: 0.001)
        let m = h.recoveryMetrics(dayKey: "2026-11-05", in: samples)
        XCTAssertEqual(m.first { $0.source == .whoop }?.hrvMethod, "RMSSD")
        XCTAssertEqual(m.first { $0.source == .appleWatch }?.hrvMethod, "SDNN")
    }

    func testMissingDaysStayNilAndBaselineNeedsMinimumDays() {
        let samples = [1, 2, 5].map { TS.sample(.restingHeartRate, 55, day: $0, source: .whoop) }
        let series = h.series(.restingHeartRate, source: .whoop, days: 5, endingAt: TS.date(5), in: samples)
        XCTAssertEqual(series.map { $0.value == nil }, [false, false, true, true, false])
        XCTAssertNil(h.baseline(.restingHeartRate, source: .whoop, before: TS.date(6), in: samples))
    }

    func testSleepAggregatesStagesPerSource() {
        let samples = [
            TS.sample(.sleepDuration, 200, day: 4, source: .appleWatch, id: "a"),
            TS.sample(.sleepDuration, 220, day: 4, source: .appleWatch, id: "b"),
            TS.sample(.sleepDuration, 410, day: 4, source: .whoop, channel: .whoopAPI),
        ]
        XCTAssertEqual(h.resolve(.sleepDuration, dayKey: "2026-11-04", in: samples)?.value, 410)
        XCTAssertEqual(h.resolve(.sleepDuration, dayKey: "2026-11-04", in: samples)?.alternatives[.appleWatch], 420)
    }

    func testAlerts() {
        var samples: [VitalSample] = []
        for d in 1...14 { samples.append(TS.sample(.restingHeartRate, 55, day: d, source: .whoop, channel: .whoopAPI)) }
        for d in 15...17 { samples.append(TS.sample(.restingHeartRate, 67, day: d, source: .whoop, channel: .whoopAPI)) }
        let alerts = VitalAlertEvaluator().dailyAlerts(on: TS.date(17), samples: samples)
        let rhr = alerts.first { $0.id == "rhr-elevated" }
        XCTAssertNotNil(rhr)
        XCTAssertEqual(rhr?.severity, .warning, "Drei Tage in Folge deutlich erhöht")
        XCTAssertEqual(rhr?.suggestsMedicalCheck, true)
        let single = VitalAlertEvaluator().dailyAlerts(on: TS.date(15), samples: samples).first { $0.id == "rhr-elevated" }
        XCTAssertEqual(single?.severity, .caution, "Einzelner erhöhter Tag: nur Hinweis")

        var p = UserProfile.initial()
        XCTAssertNil(VitalAlertEvaluator().workoutAlert(currentBpm: 130, profile: p, now: TS.date(2)))
        XCTAssertEqual(VitalAlertEvaluator().workoutAlert(currentBpm: 155, profile: p, now: TS.date(2))?.id, "hr-high")
        XCTAssertEqual(VitalAlertEvaluator().workoutAlert(currentBpm: 175, profile: p, now: TS.date(2))?.suggestsMedicalCheck, true)
        p.health.heartRateUpperLimit = 125
        XCTAssertEqual(VitalAlertEvaluator().workoutAlert(currentBpm: 130, profile: p, now: TS.date(2))?.id, "hr-limit")
    }
}

final class AssistantTests: XCTestCase {
    let assistant = TrainingAssistant()
    var plan: TrainingPlan { TS.plan() }

    func ctx(profile: UserProfile = .initial(), checkIn: ReadinessCheckIn? = ReadinessCheckIn(sleepQuality: 4, energy: 4, soreness: 2),
             history: [WorkoutSession] = [], pain: [PainReport] = [], vitals: [VitalSample] = [], now: Date = TS.date(16, 17),
             workout: Int = 0) -> AssistantContext {
        AssistantContext(now: now, profile: profile, plannedWorkout: plan.weeks[2].workouts[workout], history: history,
                         checkIn: checkIn, painReports: pain, vitals: vitals)
    }

    func goodRecovery(day: Int = 16) -> [VitalSample] {
        [TS.sample(.recoveryScore, 95, day: day, source: .whoop, channel: .whoopAPI),
         TS.sample(.sleepDuration, 480, day: day, source: .whoop, channel: .whoopAPI)]
    }

    func testAsPlannedWhenAllFine() {
        let r = assistant.recommend(ctx(vitals: goodRecovery()))
        XCTAssertEqual(r.kind, .asPlanned)
        XCTAssertTrue(r.missingData.contains("Ruhepuls mit persönlicher Basislinie"), "Fehlende Daten werden benannt")
        XCTAssertTrue(r.missingData.contains("HRV-Trend"))
    }

    func testWarningSymptomsBlockTrainingWithoutOverride() {
        let r = assistant.recommend(ctx(checkIn: ReadinessCheckIn(hasWarningSymptoms: true), vitals: goodRecovery()))
        XCTAssertEqual(r.kind, .noTrainingSeeDoctor)
        XCTAssertFalse(r.userOverrideAllowed)
        XCTAssertNotNil(r.medicalNotice)
        XCTAssertEqual(r.intensityFactor, 0)
    }

    func testFeverPausesAndNoOverride() {
        let r = assistant.recommend(ctx(checkIn: ReadinessCheckIn(hasFever: true)))
        XCTAssertEqual(r.kind, .extraRecovery)
        XCTAssertFalse(r.userOverrideAllowed)
    }

    func testReturnAfterFeverNeverAsPlannedEvenWithPerfectRecovery() {
        var p = UserProfile.initial()
        p.programStatus = .returning(after: .feverishIllness, since: TS.date(10))
        let r = assistant.recommend(ctx(profile: p, vitals: goodRecovery()))
        XCTAssertGreaterThanOrEqual(r.kind, .reduceIntensity)
        XCTAssertTrue(r.hits.contains { $0.ruleId == "S4" })
        XCTAssertNotNil(r.medicalNotice)
    }

    func testGoodRecoveryDoesNotOverrideLoadRules() {
        let prior = TS.date(15, 18)   // gestern intensive Einheit
        let s = WorkoutSession(plannedWorkoutId: nil, dayType: .conditioning, startedAt: prior, endedAt: prior + 2400,
                               state: .completed, exercises: [])
        let r = assistant.recommend(ctx(history: [s], vitals: goodRecovery()))
        XCTAssertEqual(r.kind, .mobilityInstead)
        XCTAssertTrue(r.hits.contains { $0.ruleId == "L1" })
        XCTAssertEqual(r.suggestedDayType, .recovery)
    }

    func testVitalRulesSameSourceAndCombination() {
        var v: [VitalSample] = []
        for d in 1...15 { v.append(TS.sample(.restingHeartRate, 55, day: d, source: .whoop, channel: .whoopAPI)) }
        for d in 1...15 { v.append(TS.sample(.hrvRMSSD, 50, day: d, source: .whoop, channel: .whoopAPI)) }
        v.append(TS.sample(.restingHeartRate, 64, day: 16, source: .whoop, channel: .whoopAPI))
        var r = assistant.recommend(ctx(vitals: v))
        XCTAssertEqual(r.kind, .reduceIntensity)
        XCTAssertTrue(r.hits.contains { $0.ruleId == "V1" })
        v.append(TS.sample(.hrvRMSSD, 30, day: 16, source: .whoop, channel: .whoopAPI))
        r = assistant.recommend(ctx(vitals: v))
        XCTAssertEqual(r.kind, .mobilityInstead)
        XCTAssertTrue(r.hits.contains { $0.ruleId == "V5" })
        // Ein Apple-Watch-Ruhepuls ohne eigene Basislinie wird NICHT gegen die WHOOP-Basislinie verglichen
        var p = SourcePriorities.standard
        p.order[.restingHeartRate] = [.appleWatch, .whoop]
        let onlyWatchToday = v.filter { !($0.type == .restingHeartRate && DayKey.string(for: $0.end!) == "2026-11-16") }
            + [TS.sample(.restingHeartRate, 80, day: 16, source: .appleWatch)]
        let r2 = TrainingAssistant(harmonizer: VitalHarmonizer(priorities: p)).recommend(ctx(vitals: onlyWatchToday))
        XCTAssertFalse(r2.hits.contains { $0.ruleId == "V1" })
    }

    func testPainAndSubjectiveRules() {
        let r1 = assistant.recommend(ctx(pain: [PainReport(date: TS.date(15), region: .lumbarSpine, intensity: 7)]))
        XCTAssertEqual(r1.kind, .mobilityInstead)
        XCTAssertNotNil(r1.medicalNotice)
        let r2 = assistant.recommend(ctx(checkIn: ReadinessCheckIn(sleepQuality: 2, energy: 3, soreness: 2)))
        XCTAssertEqual(r2.kind, .adjustReps)
        XCTAssertEqual(r2.intensityFactor, 0.9)
        let r3 = assistant.recommend(ctx(checkIn: nil))
        XCTAssertTrue(r3.missingData.contains("Selbsteinschätzung vor dem Training"))
    }

    func testCardioRestrictionIsDocumentedButNotEscalating() {
        var p = UserProfile.initial()
        p.health.hasCardiovascularRestriction = true
        let r = assistant.recommend(ctx(profile: p))
        XCTAssertTrue(r.hits.contains { $0.ruleId == "S5" })
    }
}
