import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FitnessCore

final class WhoopTests: XCTestCase {
    let config = WhoopConfiguration(clientId: "client-123", redirectURI: "kbtrx://oauth/whoop",
                                    brokerBaseURL: URL(string: "https://broker.example.org")!)

    static let recoveryJSON = """
    {"records":[
      {"cycle_id":93845,"sleep_id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","user_id":1,
       "created_at":"2026-11-03T06:25:44.774Z","updated_at":"2026-11-03T06:25:44.774Z","score_state":"SCORED",
       "score":{"user_calibrating":false,"recovery_score":44,"resting_heart_rate":64,"hrv_rmssd_milli":31.81,
                "spo2_percentage":95.6875,"skin_temp_celsius":33.7}},
      {"cycle_id":93846,"sleep_id":"aaaa","user_id":1,"created_at":"2026-11-04T06:25:44Z",
       "updated_at":"2026-11-04T06:25:44Z","score_state":"PENDING_SCORE"},
      {"cycle_id":93847,"sleep_id":"bbbb","user_id":1,"created_at":"2026-11-05T06:25:44Z",
       "updated_at":"2026-11-05T06:25:44Z","score_state":"SCORED",
       "score":{"user_calibrating":true,"recovery_score":60,"resting_heart_rate":58,"hrv_rmssd_milli":40}}
    ],"next_token":null}
    """

    static let sleepJSON = """
    {"records":[{"id":"ecfc6a15-4661-442f-a9a4-f160dd7afae8","cycle_id":93845,"user_id":1,
      "created_at":"2026-11-03T06:00:00Z","updated_at":"2026-11-03T06:00:00Z",
      "start":"2026-11-02T22:25:44.774Z","end":"2026-11-03T06:16:00.000Z","timezone_offset":"+01:00","nap":false,
      "score_state":"SCORED","score":{"stage_summary":{"total_in_bed_time_milli":28215000,"total_awake_time_milli":1620000,
        "total_no_data_time_milli":0,"total_light_sleep_time_milli":14400000,"total_slow_wave_sleep_time_milli":5400000,
        "total_rem_sleep_time_milli":6795000,"sleep_cycle_count":4,"disturbance_count":10},
        "respiratory_rate":15.2,"sleep_performance_percentage":88}},
      {"id":"nap-1","cycle_id":93845,"user_id":1,"created_at":"2026-11-03T14:00:00Z","updated_at":"2026-11-03T14:00:00Z",
       "start":"2026-11-03T13:00:00Z","end":"2026-11-03T13:30:00Z","timezone_offset":"+01:00","nap":true,"score_state":"SCORED",
       "score":{"stage_summary":{"total_light_sleep_time_milli":1500000}}}
    ],"next_token":""}
    """

    func testDecodeAndMapOnlyScoredData() throws {
        let rec = try WhoopDate.decoder.decode(WhoopPage<WhoopRecovery>.self, from: Data(Self.recoveryJSON.utf8)).records
        let slp = try WhoopDate.decoder.decode(WhoopPage<WhoopSleep>.self, from: Data(Self.sleepJSON.utf8)).records
        let s = WhoopMapper.samples(recoveries: rec, sleeps: slp, cycles: [], workouts: [])
        let recovery = s.filter { $0.type == .recoveryScore }
        XCTAssertEqual(recovery.map(\.value), [44, 60], "PENDING_SCORE erzeugt keinen Wert")
        XCTAssertEqual(recovery[1].quality, .calibrating)
        let hrv = s.first { $0.type == .hrvRMSSD }!
        XCTAssertEqual(hrv.value, 31.81, accuracy: 0.001)
        XCTAssertEqual(hrv.unit, .milliseconds)
        XCTAssertEqual(hrv.end, slp[0].end, "Recovery dem Aufwachzeitpunkt zugeordnet")
        let sleep = s.filter { $0.type == .sleepDuration }
        XCTAssertEqual(sleep.count, 1, "Nickerchen nicht als Nachtschlaf")
        XCTAssertEqual(sleep[0].value, (14400000 + 5400000 + 6795000) / 60000, accuracy: 0.01)
        XCTAssertEqual(s.first { $0.type == .sleepDeep }?.value, 90)
        XCTAssertTrue(s.allSatisfy { $0.source == .whoop && $0.channel == .whoopAPI && $0.sourceRecordId != nil })
    }

    func testAuthorizationURLAndCallback() throws {
        let auth = WhoopAuthorization(config: config)
        let state = WhoopAuthorization.makeState()
        XCTAssertGreaterThanOrEqual(state.count, 8)
        let url = auth.authorizationURL(state: state)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "scope" }?.value, "read:recovery read:sleep read:cycles read:workout offline")
        XCTAssertEqual(items.first { $0.name == "client_id" }?.value, "client-123")
        XCTAssertFalse(url.absoluteString.contains("secret"))
        XCTAssertEqual(try auth.code(fromCallback: URL(string: "kbtrx://oauth/whoop?code=abc&state=\(state)")!, expectedState: state), "abc")
        XCTAssertThrowsError(try auth.code(fromCallback: URL(string: "kbtrx://oauth/whoop?code=abc&state=evil")!, expectedState: state))
        XCTAssertThrowsError(try auth.code(fromCallback: URL(string: "kbtrx://oauth/whoop?error=access_denied&state=\(state)")!, expectedState: state))
    }

    func testPaginationRefreshOn401AndTokenPersistence() async throws {
        let tokens = InMemoryTokenStore()
        let now = TS.date(5)
        try tokens.saveToken(OAuthToken(accessToken: "old", refreshToken: "r1", expiresAt: now + 3600, scope: ""), for: WhoopAuthorization.tokenKey)
        var calls = 0
        let http = MockHTTP { req in
            calls += 1
            let url = req.url!.absoluteString
            if url.hasPrefix("https://broker.example.org/whoop/refresh") {
                let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: String]
                XCTAssertEqual(body["refresh_token"], "r1")
                return (200, Data(#"{"access_token":"new","refresh_token":"r2","expires_in":3600,"scope":"read:recovery"}"#.utf8), [:])
            }
            let auth = req.value(forHTTPHeaderField: "Authorization")
            if auth == "Bearer old" { return (401, Data(), [:]) }
            XCTAssertEqual(auth, "Bearer new")
            if url.contains("nextToken=page2") {
                return (200, Data(#"{"records":[{"id":2,"start":"2026-11-04T06:00:00Z","score_state":"SCORED","score":{"strain":8.1}}],"next_token":null}"#.utf8), [:])
            }
            return (200, Data(#"{"records":[{"id":1,"start":"2026-11-03T06:00:00Z","end":"2026-11-04T06:00:00Z","score_state":"SCORED","score":{"strain":12.5}}],"next_token":"page2"}"#.utf8), [:])
        }
        let client = WhoopClient(config: config, http: http, tokens: tokens, now: { now })
        let cycles = try await client.collection("v2/cycle", start: now - 86400 * 7, end: now, as: WhoopCycle.self)
        XCTAssertEqual(cycles.map(\.id), [1, 2])
        XCTAssertEqual(try tokens.loadToken(for: WhoopAuthorization.tokenKey)?.accessToken, "new")
        XCTAssertEqual(try tokens.loadToken(for: WhoopAuthorization.tokenKey)?.refreshToken, "r2")
        XCTAssertTrue(http.requests.allSatisfy { $0.url?.scheme == "https" })
        XCTAssertTrue(http.requests.first!.url!.absoluteString.contains("limit=25"))
    }

    func testRateLimitAndMissingTokenErrors() async throws {
        let tokens = InMemoryTokenStore()
        let client = WhoopClient(config: config, http: MockHTTP { _ in (429, Data(), ["Retry-After": "30"]) }, tokens: tokens)
        do { _ = try await client.collection("v2/cycle", start: Date(), end: Date(), as: WhoopCycle.self); XCTFail() }
        catch { XCTAssertEqual(error as? ProviderError, .notAuthorized) }
        try tokens.saveToken(OAuthToken(accessToken: "a", refreshToken: nil, expiresAt: Date() + 3600, scope: ""), for: WhoopAuthorization.tokenKey)
        do { _ = try await client.collection("v2/cycle", start: Date(), end: Date(), as: WhoopCycle.self); XCTFail() }
        catch { XCTAssertEqual(error as? ProviderError, .rateLimited(retryAfter: 30)) }
    }

    func testExpiredTokenWithoutRefreshIsNotAuthorized() async throws {
        let tokens = InMemoryTokenStore()
        try tokens.saveToken(OAuthToken(accessToken: "a", refreshToken: nil, expiresAt: Date() - 10, scope: ""), for: WhoopAuthorization.tokenKey)
        let client = WhoopClient(config: config, http: MockHTTP { _ in (200, Data(), [:]) }, tokens: tokens)
        do { _ = try await client.collection("v2/cycle", start: Date(), end: Date(), as: WhoopCycle.self); XCTFail() }
        catch { XCTAssertEqual(error as? ProviderError, .notAuthorized) }
        await client.disconnect()
        XCTAssertFalse(client.isConnected)
    }
}

final class HealthMappingTests: XCTestCase {
    func dto(_ type: String, _ v: Double, bundle: String, model: String? = nil, cat: Int? = nil) -> HealthSampleDTO {
        HealthSampleDTO(typeIdentifier: type, value: v, start: TS.date(3, 1), end: TS.date(3, 2), uuid: UUID().uuidString,
                        sourceBundleId: bundle, sourceName: "x", deviceModel: model, categoryValue: cat)
    }

    func testSourceClassification() {
        XCTAssertEqual(HealthSourceClassifier.classify(bundleId: "com.garmin.connect.mobile", deviceModel: nil), .garmin)
        XCTAssertEqual(HealthSourceClassifier.classify(bundleId: "com.whoop.iphone", deviceModel: nil), .whoop)
        XCTAssertEqual(HealthSourceClassifier.classify(bundleId: "com.apple.health.81A7", deviceModel: "Watch"), .appleWatch)
        XCTAssertEqual(HealthSourceClassifier.classify(bundleId: "com.apple.health.81A7", deviceModel: "iPhone"), .iPhone)
        XCTAssertEqual(HealthSourceClassifier.classify(bundleId: "de.example.kbtrx", deviceModel: nil, ownBundleId: "de.example.kbtrx"), .app)
        XCTAssertEqual(HealthSourceClassifier.classify(bundleId: "com.other", deviceModel: nil), .otherHealthApp)
    }

    func testSleepStagesAndEstimatedEnergy() {
        let core = HealthSampleMapper.map(dto(HealthTypeID.sleepAnalysis, 0, bundle: "com.garmin.connect.mobile", cat: 3))
        XCTAssertEqual(Set(core.map(\.type)), [.sleepDuration, .sleepLight])
        XCTAssertEqual(core[0].value, 60)
        XCTAssertTrue(HealthSampleMapper.map(dto(HealthTypeID.sleepAnalysis, 0, bundle: "x", cat: 0)).isEmpty, "Im Bett ≠ Schlaf")
        XCTAssertEqual(HealthSampleMapper.map(dto(HealthTypeID.sleepAnalysis, 0, bundle: "x", cat: 2)).first?.type, .sleepAwake)
        XCTAssertEqual(HealthSampleMapper.map(dto(HealthTypeID.activeEnergy, 300, bundle: "x")).first?.quality, .estimated)
        XCTAssertEqual(HealthSampleMapper.map(dto(HealthTypeID.hrvSDNN, 42, bundle: "com.apple.health", model: "Watch")).first?.type, .hrvSDNN)
        XCTAssertTrue(HealthSampleMapper.map(dto("HKQuantityTypeIdentifierUnknown", 1, bundle: "x")).isEmpty)
    }

    func testGarminAvailabilityReport() {
        let samples = [HealthTypeID.restingHeartRate, HealthTypeID.steps].flatMap {
            HealthSampleMapper.map(dto($0, 50, bundle: "com.garmin.connect.mobile"))
        } + HealthSampleMapper.map(dto(HealthTypeID.hrvSDNN, 40, bundle: "com.apple.health", model: "Watch"))
        let report = GarminViaHealth.availability(from: samples)
        XCTAssertEqual(Set(report.availableTypes), [.restingHeartRate, .steps])
        XCTAssertTrue(report.missingTypes.contains(.hrvSDNN), "Apple-Watch-HRV zählt nicht als Garmin-Daten")
    }
}

final class AnalyticsTests: XCTestCase {
    func sessions() -> [WorkoutSession] {
        DemoDataGenerator().sessions(plan: TS.plan(), upTo: TS.date(21))
    }

    func testSummaryAndTonnageOnlyKettlebell() {
        let s = sessions()
        XCTAssertEqual(s.count, 9)
        let sum = TrainingAnalytics().summary(s, period: .days30, endingAt: TS.date(21), plan: TS.plan())
        XCTAssertEqual(sum.sessions, 9)
        XCTAssertGreaterThan(sum.tonnageKg, 0)
        let trxOnly = s.flatMap(\.allSets).filter { TS.library[$0.exerciseId]!.load.kind != .kettlebell }
        XCTAssertTrue(trxOnly.allSatisfy { $0.tonnageKg == 0 })
        XCTAssertEqual(sum.adherence, 0, "Demo-Einheiten markieren den Plan nicht")
        XCTAssertNotNil(sum.averageRPE)
    }

    func testBucketsPerPeriod() {
        let a = TrainingAnalytics()
        let end = TS.date(21)
        XCTAssertEqual(a.buckets(.days7, endingAt: end).count, 7)
        XCTAssertEqual(a.buckets(.days30, endingAt: end).count, 30)
        XCTAssertEqual(a.buckets(.weeks8, endingAt: end).count, 8)
        XCTAssertEqual(a.buckets(.months3, endingAt: end).count, 13)
        XCTAssertEqual(a.buckets(.months12, endingAt: end).count, 12)
        let weekly = a.series(.sessions, sessions: sessions(), period: .weeks8, endingAt: end)
        XCTAssertEqual(weekly.suffix(3).map(\.value), [3, 3, 3])
        XCTAssertEqual(weekly.first?.value, 0)
        let rpe = a.series(.averageRPE, sessions: sessions(), period: .weeks8, endingAt: end)
        XCTAssertNil(rpe.first?.value, "Keine Daten ≠ 0")
        XCTAssertTrue(weekly.last!.label.hasPrefix("KW"))
    }

    func testStrengthProgressAndVitalSeries() {
        let pts = TrainingAnalytics().strengthProgress(exerciseId: "kb_deadlift", sessions: sessions())
        XCTAssertEqual(pts.map(\.maxWeightKg), [12, 12, 12, 12, 16, 16], "Technikphase leichter, ab Woche 3 empfohlenes Gewicht")
        let vit = DemoDataGenerator().vitals(days: 30, endingAt: TS.date(21))
        let series = TrainingAnalytics().vitalSeries(.restingHeartRate, source: .whoop, samples: vit, period: .days7,
                                                     endingAt: TS.date(21), harmonizer: VitalHarmonizer())
        XCTAssertEqual(series.count, 7)
        XCTAssertTrue(series.allSatisfy { $0.value != nil })
        XCTAssertEqual(TrainingAnalytics().availableSources(.restingHeartRate, samples: vit), [.appleWatch, .whoop])
    }
}
