import XCTest
@testable import FitnessCore

final class PersistenceTests: XCTestCase {
    func testRoundTripAllCollections() throws {
        let dir = TS.tempDir()
        let repo = try AppRepository(store: LocalStore(directory: dir))
        var p = repo.profile
        p.bodyWeightKg = 90
        p.restrictions = [PhysicalRestriction(region: .shoulder, severity: .moderate, note: "Impingement früher")]
        try repo.updateProfile(p)
        try repo.setPlan(TS.plan())
        var run = WorkoutRun.from(planned: repo.plan!.weeks[0].workouts[0], now: TS.date(2, 18))
        run.start(at: TS.date(2, 18))
        run.completeSet(at: TS.date(2, 18) + 60)
        run.recordHeartRate([HeartRatePoint(date: TS.date(2, 18) + 30, bpm: 101)])
        run.finish(at: TS.date(2, 19), feedback: PostWorkoutFeedback(rpe: 6))
        try repo.completeRun(run)
        try repo.addPainReport(PainReport(region: .knee, intensity: 2))
        try repo.addCheckIn(ReadinessCheckIn())

        let again = try AppRepository(store: LocalStore(directory: dir))
        XCTAssertEqual(again.profile.bodyWeightKg, 90)
        XCTAssertEqual(again.profile.restrictions.count, 1)
        XCTAssertEqual(again.plan?.id, repo.plan?.id)
        XCTAssertEqual(again.plan?.weeks[0].workouts[0].completedSessionId, run.session.id, "Plan markiert absolvierte Einheit")
        XCTAssertEqual(again.sessions.count, 1)
        XCTAssertEqual(again.sessions[0].feedback?.rpe, 6)
        XCTAssertNil(again.activeRun)
        XCTAssertEqual(again.vitals.filter { $0.type == .heartRate && $0.sessionId == run.session.id }.count, 1)
        XCTAssertEqual(again.painReports.count, 1)
        XCTAssertEqual(again.checkIns.count, 1)
    }

    func testCorruptedFileFallsBackToBackup() throws {
        let dir = TS.tempDir()
        let repo = try AppRepository(store: LocalStore(directory: dir))
        var p = repo.profile
        p.displayName = "Version 1"
        try repo.updateProfile(p)
        p.displayName = "Version 2"
        try repo.updateProfile(p)
        try Data("{ kaputt".utf8).write(to: dir.appendingPathComponent("profile.json"))
        let store = try LocalStore(directory: dir)
        let again = try AppRepository(store: store)
        XCTAssertEqual(again.profile.displayName, "Version 1")
        XCTAssertEqual(store.recoveredFromBackup, ["profile"])
    }

    func testMigrationsRunInOrderAndNewerSchemaRejected() throws {
        let dir = TS.tempDir()
        let store = try LocalStore(directory: dir)
        try store.save(StoreMeta(schemaVersion: 0, createdAt: Date()), as: "meta")
        // Altes Profilformat ohne neue Felder – Migration ergänzt das Ausgangsprofil
        let migration = SchemaMigration(fromVersion: 0, description: "Testmigration") { s in
            try s.save(UserProfile.initial(), as: "profile")
        }
        _ = try AppRepository(store: store, migrations: [migration])
        XCTAssertEqual(try store.load(StoreMeta.self, from: "meta")?.schemaVersion, AppRepository.currentSchemaVersion)

        let store2 = try LocalStore(directory: TS.tempDir())
        try store2.save(StoreMeta(schemaVersion: 0, createdAt: Date()), as: "meta")
        XCTAssertThrowsError(try AppRepository(store: store2)) { XCTAssertTrue($0 is MigrationError) }

        let store3 = try LocalStore(directory: TS.tempDir())
        try store3.save(StoreMeta(schemaVersion: 99, createdAt: Date()), as: "meta")
        XCTAssertThrowsError(try AppRepository(store: store3))
    }

    func testDemoDataMarkedAndDeletable() throws {
        let repo = try AppRepository(store: LocalStore(directory: TS.tempDir()))
        try repo.setPlan(TS.plan())
        let demo = DemoDataGenerator().sessions(plan: repo.plan!, upTo: TS.date(14))
        XCTAssertEqual(demo.count, 6)
        XCTAssertTrue(demo.allSatisfy(\.isDemo))
        for s in demo { try repo.upsertSession(s) }
        try repo.ingestVitals(DemoDataGenerator().vitals(days: 10, endingAt: TS.date(14)))
        XCTAssertTrue(repo.vitals.allSatisfy { $0.quality == .demo })
        XCTAssertTrue(repo.hasDemoData)
        // echte Einheit bleibt erhalten
        let real = WorkoutSession(plannedWorkoutId: nil, dayType: .strength, startedAt: TS.date(14), state: .completed, exercises: [])
        try repo.upsertSession(real)
        try repo.deleteDemoData()
        XCTAssertFalse(repo.hasDemoData)
        XCTAssertEqual(repo.sessions.map(\.id), [real.id])
    }

    func testDeleteAllAndExport() throws {
        let dir = TS.tempDir()
        let repo = try AppRepository(store: LocalStore(directory: dir))
        try repo.setPlan(TS.plan())
        for s in DemoDataGenerator().sessions(plan: repo.plan!, upTo: TS.date(7)) { try repo.upsertSession(s) }
        let json = try DataExporter().json(from: repo)
        let text = String(decoding: json, as: UTF8.self)
        XCTAssertTrue(text.contains("\"sessions\""))
        XCTAssertFalse(text.lowercased().contains("access_token"))
        let decoded = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        XCTAssertEqual((decoded?["sessions"] as? [Any])?.count, 3)
        let csv = DataExporter().setsCSV(sessions: repo.sessions, library: TS.library)
        XCTAssertTrue(csv.hasPrefix("Datum;Einheit;"))
        XCTAssertTrue(csv.contains("Kettlebell Goblet Squat"))
        XCTAssertGreaterThan(csv.split(separator: "\n").count, 20)

        try repo.deleteAllPersonalData()
        XCTAssertTrue(repo.sessions.isEmpty)
        XCTAssertNil(repo.plan)
        let reopened = try AppRepository(store: LocalStore(directory: dir))
        XCTAssertTrue(reopened.sessions.isEmpty)
        XCTAssertNil(reopened.plan)
    }

    func testCSVEscaping() {
        XCTAssertEqual(DataExporter.csvField("a;b"), "\"a;b\"")
        XCTAssertEqual(DataExporter.csvField("x\"y"), "\"x\"\"y\"")
        XCTAssertEqual(DataExporter.csvField("plain"), "plain")
    }
}

struct MockProvider: VitalDataProvider {
    let kind: IntegrationKind
    var result: Result<[VitalSample], ProviderError>
    func fetch(since: Date?, cursor: String?, until: Date) async throws -> ProviderBatch {
        switch result {
        case .success(let s): return ProviderBatch(samples: s, cursor: "anchor-1", syncedUntil: until)
        case .failure(let e): throw e
        }
    }
}

final class SyncTests: XCTestCase {
    func repo() throws -> AppRepository {
        let r = try AppRepository(store: LocalStore(directory: TS.tempDir()))
        for k in [IntegrationKind.whoop, .appleHealth] {
            var d = r.device(k); d.isEnabled = true; try r.updateDevice(d)
        }
        return r
    }

    func testSuccessfulSyncUpdatesStateAndStatus() async throws {
        let r = try repo()
        let c = SyncCoordinator(repository: r, providers: [
            MockProvider(kind: .whoop, result: .success([TS.sample(.recoveryScore, 70, day: 3, source: .whoop, channel: .whoopAPI)])),
        ])
        let reports = await c.syncAll(now: TS.date(3, 12))
        XCTAssertEqual(reports.first?.result?.inserted, 1)
        let st = r.syncState(.whoop)
        XCTAssertEqual(st.lastSuccess, TS.date(3, 12))
        XCTAssertEqual(st.cursor, "anchor-1")
        XCTAssertNil(st.lastError)
        XCTAssertEqual(r.device(.whoop).status, .connected)
        // zweite Synchronisierung: keine Duplikate
        _ = await c.syncAll(now: TS.date(3, 13))
        XCTAssertEqual(r.vitals.count, 1)
        XCTAssertEqual(r.syncState(.whoop).lastImportedCount, 0)
    }

    func testFailureIsVisibleAndLocalDataUntouched() async throws {
        let r = try repo()
        try r.setPlan(TS.plan())
        let s = WorkoutSession(plannedWorkoutId: nil, dayType: .strength, startedAt: TS.date(2), state: .completed, exercises: [])
        try r.upsertSession(s)
        let c = SyncCoordinator(repository: r, providers: [
            MockProvider(kind: .whoop, result: .failure(.network("offline"))),
            MockProvider(kind: .appleHealth, result: .success([TS.sample(.steps, 5000, day: 2, source: .iPhone)])),
        ])
        _ = await c.syncAll(now: TS.date(3))
        _ = await c.syncAll(now: TS.date(3, 9))
        let st = r.syncState(.whoop)
        XCTAssertEqual(st.consecutiveFailures, 2)
        XCTAssertEqual(st.lastError?.isRecoverable, true)
        XCTAssertNotNil(st.lastError?.message)
        XCTAssertEqual(r.sessions.count, 1, "Trainingsdaten bleiben erhalten")
        XCTAssertEqual(r.vitals.count, 1, "Andere Quelle wurde trotzdem synchronisiert")
    }

    func testAuthErrorMarksDeviceAndDisabledSourceSkipped() async throws {
        let r = try repo()
        var gd = r.device(.garminViaHealth); gd.isEnabled = false; try r.updateDevice(gd)
        let c = SyncCoordinator(repository: r, providers: [
            MockProvider(kind: .whoop, result: .failure(.notAuthorized)),
            MockProvider(kind: .garminViaHealth, result: .success([TS.sample(.steps, 1, day: 1, source: .garmin)])),
        ])
        let reports = await c.syncAll(now: TS.date(3))
        XCTAssertEqual(reports.map(\.kind), [.whoop])
        if case .error = r.device(.whoop).status {} else { XCTFail("Gerätestatus sollte Fehler zeigen") }
        XCTAssertEqual(r.syncState(.whoop).lastError?.isRecoverable, false)
    }

    func testGarminDirectUnavailableAndDefaults() async throws {
        let r = try repo()
        if case .unavailable = r.device(.garminPersonalAPI).status {} else { XCTFail() }
        var d = r.device(.garminPersonalAPI); d.isEnabled = true; try r.updateDevice(d)
        let c = SyncCoordinator(repository: r, providers: [GarminDirectProvider()])
        let rep = await c.syncAll(now: TS.date(3))
        if case .unavailable = rep.first?.error {} else { XCTFail() }
    }

    func testRetryBackoff() {
        XCTAssertEqual(SyncCoordinator.retryDelay(afterFailures: 1), 60)
        XCTAssertEqual(SyncCoordinator.retryDelay(afterFailures: 3), 240)
        XCTAssertEqual(SyncCoordinator.retryDelay(afterFailures: 30), 6 * 3600)
    }
}

final class WatchProtocolTests: XCTestCase {
    func testOutboxAckAndInboxDedup() throws {
        var out = MessageOutbox()
        let t = TS.date(2)
        let e1 = out.enqueue(.heartRate([HeartRatePoint(date: t, bpm: 90)]), at: t)
        let e2 = out.enqueue(.workoutState(WatchWorkoutState(state: .running, startDate: t, elapsedSeconds: 5, sessionId: nil)), at: t)
        let e3 = out.enqueue(.command(.pause), at: t)
        XCTAssertEqual(out.pending.map(\.seq), [1, 2, 3])
        out.acknowledge(upTo: 2)
        XCTAssertEqual(out.pending.map(\.seq), [3])

        var inbox = MessageInbox()
        XCTAssertTrue(inbox.accept(e1))
        XCTAssertTrue(inbox.accept(e3))
        XCTAssertFalse(inbox.accept(e1), "doppelt (Mirroring + transferUserInfo)")
        XCTAssertTrue(inbox.accept(e2))
        XCTAssertEqual(inbox.highestContiguous, 3)
        XCTAssertFalse(inbox.accept(e3))

        let decoded = try WatchEnvelope.decode(e2.encoded())
        XCTAssertEqual(decoded, e2)
    }

    func testOutboxBoundedDropsLiveHeartRateFirst() {
        var out = MessageOutbox()
        out.maxPending = 3
        let t = TS.date(2)
        out.enqueue(.command(.pause), at: t)
        out.enqueue(.heartRate([]), at: t)
        out.enqueue(.command(.resume), at: t)
        out.enqueue(.command(.end), at: t)
        XCTAssertEqual(out.pending.count, 3)
        XCTAssertFalse(out.pending.contains { if case .heartRate = $0.message { return true }; return false })
    }
}
