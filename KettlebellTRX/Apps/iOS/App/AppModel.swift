import Foundation
import Observation
import SwiftUI
import FitnessCore

/// Zentraler App-Zustand (UI-Schicht). Fachlogik liegt vollständig in `FitnessCore`.
@MainActor
@Observable
final class AppModel {
    // Infrastruktur (nicht beobachtet)
    @ObservationIgnored let repo: AppRepository
    @ObservationIgnored let library: ExerciseLibrary
    @ObservationIgnored let health: HealthKitService
    @ObservationIgnored let watch: WatchWorkoutBridge
    @ObservationIgnored let tokenStore: KeychainTokenStore
    @ObservationIgnored private var sync: SyncCoordinator?

    /// Änderungszähler – UI-Abhängigkeiten auf Repository-Daten laufen hierüber.
    private(set) var version = 0
    var errorMessage: String?
    var isSyncing = false
    private(set) var lastRecommendation: Recommendation?
    private(set) var liveAlert: VitalAlert?
    private(set) var run: WorkoutRun?
    private(set) var recoveredFromBackup: [String] = []

    init() {
        var startupError: String?
        var recovered: [String] = []
        let repository: AppRepository
        do {
            let store = try LocalStore(directory: LocalStore.defaultDirectory())
            repository = try AppRepository(store: store)
            recovered = store.recoveredFromBackup
        } catch {
            // Letzter Ausweg: temporärer Speicher, der Fehler wird sichtbar angezeigt.
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("KettlebellTRX-recovery")
            repository = try! AppRepository(store: LocalStore(directory: tmp))
            startupError = "Lokale Daten konnten nicht geladen werden: \(error.localizedDescription)"
        }
        let lib: ExerciseLibrary
        do { lib = try ExerciseLibrary.bundled() } catch {
            lib = ExerciseLibrary(exercises: [])
            startupError = "Übungsbibliothek konnte nicht geladen werden."
        }
        let hk = HealthKitService()
        repo = repository
        library = lib
        health = hk
        tokenStore = KeychainTokenStore()
        watch = WatchWorkoutBridge(healthStore: hk.store)
        // ab hier ist self vollständig initialisiert
        errorMessage = startupError
        recoveredFromBackup = recovered
        run = repository.activeRun
        watch.onHeartRate = { [weak self] points in self?.receiveHeartRate(points) }
        watch.onSummary = { [weak self] summary in self?.receiveWatchSummary(summary) }
        watch.onRemoteCommand = { [weak self] cmd in self?.handleWatchCommand(cmd) }
        rebuildSync()
        ensurePlan()
        if Self.isDemoLaunch { prepareDemo() }
    }

    /// Vorführmodus (Startargument `-demo`, z. B. für Screenshots im Simulator):
    /// Plan beginnt vor drei Wochen, gekennzeichnete Beispieldaten werden geladen.
    static var isDemoLaunch: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    private func prepareDemo() {
        guard !repo.hasDemoData else { return }
        let cal = Calendar.iso8601Monday
        let start = cal.date(byAdding: .weekOfYear, value: -3, to: cal.startOfWeek(for: Date())) ?? Date()
        regeneratePlan(start: start)
        loadDemoData()
    }

    private func touch() { version &+= 1 }

    private func attempt(_ what: String, _ body: () throws -> Void) {
        do { try body(); touch() } catch { errorMessage = "\(what): \(error.localizedDescription)" }
    }

    // MARK: Lesezugriffe (beobachtet über `version`)

    var profile: UserProfile { _ = version; return repo.profile }
    var plan: TrainingPlan? { _ = version; return repo.plan }
    var sessions: [WorkoutSession] { _ = version; return repo.sessions }
    var vitals: [VitalSample] { _ = version; return repo.vitals }
    var devices: [DeviceConnection] { _ = version; return repo.devices }
    var painReports: [PainReport] { _ = version; return repo.painReports }
    var settings: AppSettings { _ = version; return repo.settings }
    var hasDemoData: Bool { _ = version; return repo.hasDemoData }
    func syncState(_ k: IntegrationKind) -> SyncState { _ = version; return repo.syncState(k) }
    func device(_ k: IntegrationKind) -> DeviceConnection { _ = version; return repo.device(k) }

    var harmonizer: VitalHarmonizer { VitalHarmonizer(priorities: settings.sourcePriorities) }

    var nextWorkout: PlannedWorkout? { plan?.nextWorkout(from: Date()) }
    var currentWeek: Int { plan?.currentWeekIndex(at: Date()) ?? 1 }

    func exercise(_ id: String) -> Exercise? { library[id] }

    // MARK: Profil & Plan

    func ensurePlan() {
        guard repo.plan == nil else { return }
        regeneratePlan(start: Calendar.iso8601Monday.startOfWeek(for: Date()))
    }

    func regeneratePlan(start: Date) {
        let recentPain = repo.painReports.filter { Date().timeIntervalSince($0.date) < 14 * 86400 }
        let next = (repo.plan?.cycleNumber ?? 0) + 1
        let plan = PlanGenerator(library: library, profile: repo.profile).generate(startDate: start, recentPain: recentPain, cycleNumber: next)
        attempt("Plan speichern") { try repo.setPlan(plan) }
    }

    func updateProfile(_ p: UserProfile) { attempt("Profil speichern") { try repo.updateProfile(p) } }

    func updatePlannedExercise(_ e: PlannedExercise, in workout: PlannedWorkout) {
        var w = workout
        guard let i = w.exercises.firstIndex(where: { $0.id == e.id }) else { return }
        var e = e
        e.userModified = true
        w.exercises[i] = e
        attempt("Plan ändern") { try repo.updatePlannedWorkout(w) }
    }

    func replacePlannedExercise(_ e: PlannedExercise, with ex: Exercise, in workout: PlannedWorkout) {
        var updated = e
        updated.exerciseId = ex.id
        updated.targetKind = ex.defaultPrescription.targetKind
        if ex.defaultPrescription.targetKind != e.targetKind { updated.target = ex.defaultPrescription.target }
        updated.perSide = ex.defaultPrescription.perSide
        updated.weightKg = WeightSelector(available: profile.kettlebellsKg).recommended(for: ex, experience: profile.experience)
        updatePlannedExercise(updated, in: workout)
    }

    var progressionProposals: [AdjustmentProposal] {
        guard let plan else { return [] }
        return ProgressionEngine().proposals(plan: plan, history: sessions, profile: profile, library: library,
                                             currentWeek: currentWeek, painReports: painReports)
    }

    func apply(_ proposal: AdjustmentProposal) {
        guard var p = repo.plan else { return }
        ProgressionEngine().apply(proposal, to: &p)
        attempt("Anpassung übernehmen") { try repo.setPlan(p, archiveCurrent: false) }
    }

    // MARK: Gesundheit

    func addPain(_ p: PainReport) { attempt("Beschwerde speichern") { try repo.addPainReport(p) } }
    func deletePain(_ id: UUID) { attempt("Beschwerde löschen") { try repo.deletePainReport(id: id) } }

    func setProgramStatus(_ s: ProgramStatus) {
        var p = repo.profile
        p.programStatus = s
        updateProfile(p)
    }

    // MARK: Assistent

    func evaluateReadiness(checkIn: ReadinessCheckIn, for workout: PlannedWorkout?) -> Recommendation {
        // Beispieldaten fließen NIE in Empfehlungen ein.
        let ctx = AssistantContext(now: Date(), profile: repo.profile, plannedWorkout: workout,
                                   history: repo.sessions.filter { !$0.isDemo }, checkIn: checkIn, painReports: repo.painReports,
                                   vitals: repo.vitals.filter { $0.quality != .demo })
        let rec = TrainingAssistant(harmonizer: harmonizer).recommend(ctx)
        attempt("Selbsteinschätzung speichern") {
            try repo.addCheckIn(checkIn)
            try repo.addRecommendation(rec)
        }
        lastRecommendation = rec
        return rec
    }

    var dailyAlerts: [VitalAlert] { VitalAlertEvaluator(harmonizer: harmonizer).dailyAlerts(on: Date(), samples: vitals.filter { $0.quality != .demo }) }

    // MARK: Training

    /// Startet ein Training. Bei „Mobilität statt Kraft“ wird eine Regenerationseinheit erzeugt.
    func startWorkout(_ planned: PlannedWorkout, recommendation: Recommendation?, useRecoveryInstead: Bool = false,
                      painRegions: [BodyRegion] = []) {
        var workout = planned
        let pain = repo.painReports + painRegions.map { PainReport(region: $0, intensity: 5) }
        let gen = PlanGenerator(library: library, profile: repo.profile)
        if useRecoveryInstead {
            // gleiche ID: der geplante Tag gilt als (durch Regeneration ersetzt) erledigt
            workout = PlannedWorkout(id: planned.id, week: planned.week, weekday: planned.weekday, dayType: .recovery,
                                     exercises: gen.buildExercises(for: .recovery, week: planned.week, recentPain: pain))
        } else if !painRegions.isEmpty {
            // betroffene Übungen für heute ersetzen
            let filter = SafetyFilter(profile: repo.profile, recentPain: pain)
            workout.exercises = workout.exercises.map { pe in
                guard let ex = library[pe.exerciseId], filter.evaluate(ex).level == .excluded,
                      let sub = filter.safeSubstitute(for: ex, in: library) else { return pe }
                var c = pe
                c.exerciseId = sub.id
                c.substitutedFrom = ex.id
                c.substitutionReason = "Heute aktuelle Beschwerden"
                if sub.defaultPrescription.targetKind != pe.targetKind { c.targetKind = sub.defaultPrescription.targetKind; c.target = sub.defaultPrescription.target }
                c.weightKg = WeightSelector(available: repo.profile.kettlebellsKg).recommended(for: sub, experience: repo.profile.experience)
                return c
            }
        }
        let factor = min(recommendation?.intensityFactor ?? 1, repo.profile.health.intensityFactor).clamped(0.6, 1)
        var r = WorkoutRun.from(planned: workout, intensityFactor: useRecoveryInstead ? 1 : factor, now: Date(),
                                recommendationId: recommendation?.id)
        r.start(at: Date())
        run = r
        persistRun()
        watch.startWatchWorkout(sessionId: r.session.id, saveToHealth: repo.profile.consents.saveWorkoutsToAppleHealth)
        pushContextToWatch()
        if settings.keepScreenOnDuringWorkout { UIApplication.shared.isIdleTimerDisabled = true }
    }

    func mutateRun(_ change: (inout WorkoutRun, Date) -> Void) {
        guard var r = run else { return }
        let now = Date()
        change(&r, now)
        run = r
        persistRun()
        pushContextToWatch()
        RestNotifications.schedule(for: r, now: now)
    }

    /// Regelmäßig vom Player aufgerufen; liefert `true`, wenn eine Pause endete.
    @discardableResult
    func tick() -> Bool {
        guard var r = run else { return false }
        let changed = r.tick(at: Date())
        if changed {
            run = r
            persistRun()
            pushContextToWatch()
        }
        if let hr = r.heartRate.current(at: Date()) {
            liveAlert = VitalAlertEvaluator().workoutAlert(currentBpm: hr.bpm, profile: repo.profile)
        } else { liveAlert = nil }
        return changed
    }

    func pauseWorkout() { mutateRun { $0.pause(at: $1) }; watch.send(.command(.pause)) }
    func resumeWorkout() { mutateRun { $0.resume(at: $1) }; watch.send(.command(.resume)) }

    func finishWorkout(aborted: Bool, feedback: PostWorkoutFeedback?) {
        guard var r = run else { return }
        r.finish(at: Date(), aborted: aborted, feedback: feedback)
        if let f = feedback { for p in f.painReports { var p = p; p.sessionId = r.session.id; try? repo.addPainReport(p) } }
        attempt("Training speichern") { try repo.completeRun(r) }
        watch.send(.command(.end))
        let session = r.session
        run = nil
        RestNotifications.cancel()
        UIApplication.shared.isIdleTimerDisabled = false
        // Ohne Watch-Aufzeichnung: Workout auf Wunsch vom iPhone aus in Apple Health sichern.
        if repo.profile.consents.saveWorkoutsToAppleHealth, !watch.lastSessionSavedByWatch, !aborted {
            Task { await saveToHealthFromPhone(session) }
        }
    }

    func attachFeedbackToLastSession(_ f: PostWorkoutFeedback, sessionId: UUID) {
        guard var s = repo.session(id: sessionId) else { return }
        s.feedback = f
        attempt("Rückmeldung speichern") {
            try repo.upsertSession(s)
            for p in f.painReports { var p = p; p.sessionId = sessionId; try repo.addPainReport(p) }
        }
    }

    private func saveToHealthFromPhone(_ s: WorkoutSession) async {
        do {
            let uuid = try await health.saveWorkout(s)
            var updated = s
            updated.savedToAppleHealth = true
            updated.healthKitWorkoutUUID = uuid
            attempt("Health-Status speichern") { try repo.upsertSession(updated) }
        } catch {
            errorMessage = "Speichern in Apple Health fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func persistRun() {
        do { try repo.saveActiveRun(run) } catch { errorMessage = "Trainingszustand konnte nicht gesichert werden: \(error.localizedDescription)" }
    }

    private func pushContextToWatch() {
        guard let r = run, let ex = r.currentExercise else { return }
        let name = library[ex.exerciseId]?.nameDE ?? ex.exerciseId
        var restEnd: Date?
        if case .resting(let until, _) = r.phase { restEnd = until }
        watch.send(.context(WorkoutContextInfo(
            exerciseName: name, setText: "Satz \(min(r.currentSetNumber, ex.plannedSets)) von \(ex.plannedSets)",
            nextExerciseName: r.nextExercise.flatMap { library[$0.exerciseId]?.nameDE }, restEndsAt: restEnd)))
    }

    private func receiveHeartRate(_ points: [HeartRatePoint]) {
        guard var r = run else { return }
        r.recordHeartRate(points)
        run = r
        // Puls wird gebündelt gesichert (spätestens mit jeder Aktion / jedem Tick-Wechsel)
        if r.heartRate.points.count % 10 == 0 { persistRun() }
    }

    private func receiveWatchSummary(_ s: WatchWorkoutSummary) {
        // Nach Verbindungsabbruch: vollständigen Pulsverlauf nachtragen.
        if var r = run, r.session.id == s.sessionId {
            r.recordHeartRate(s.heartRate)
            run = r
            persistRun()
            return
        }
        guard let id = s.sessionId, var session = repo.session(id: id) else { return }
        var series = HeartRateSeries(source: .appleWatch)
        series.append(contentsOf: s.heartRate)
        session.heartRate = series.summary
        session.savedToAppleHealth = s.savedToHealth
        session.healthKitWorkoutUUID = s.healthKitWorkoutUUID
        attempt("Watch-Daten übernehmen") {
            try repo.upsertSession(session)
            try repo.ingestVitals(s.heartRate.map {
                VitalSample(type: .heartRate, value: $0.bpm, start: $0.date, source: .appleWatch, channel: .watchLive, sessionId: id)
            })
        }
    }

    private func handleWatchCommand(_ c: WatchCommand) {
        switch c {
        case .pause: mutateRun { $0.pause(at: $1) }
        case .resume: mutateRun { $0.resume(at: $1) }
        case .end, .discard: break   // Beenden nur am iPhone mit Rückmeldung
        }
    }

    // MARK: Geräte & Synchronisierung

    func rebuildSync() {
        var providers: [VitalDataProvider] = []
        let garminEnabled = repo.device(.garminViaHealth).isEnabled
        providers.append(HealthKitVitalProvider(service: health, kind: .appleHealth, ownBundleId: Bundle.main.bundleIdentifier,
                                                include: { src in src != .garmin && src != .whoop && src != .app }))
        if garminEnabled {
            providers.append(HealthKitVitalProvider(service: health, kind: .garminViaHealth, ownBundleId: Bundle.main.bundleIdentifier,
                                                    include: { $0 == .garmin }))
        }
        if let cfg = repo.settings.whoop, cfg.isComplete {
            providers.append(WhoopProvider(client: WhoopClient(config: cfg, tokens: tokenStore)))
        }
        providers.append(GarminDirectProvider())
        sync = SyncCoordinator(repository: repo, providers: providers)
        // WHOOP-Kopien in Apple Health ignorieren, solange WHOOP direkt angebunden ist.
        var s = repo.settings
        let whoopDirect = repo.device(.whoop).isEnabled
        if s.sourcePriorities.suppressHealthKitCopiesOf.contains(.whoop) != whoopDirect {
            if whoopDirect { s.sourcePriorities.suppressHealthKitCopiesOf.insert(.whoop) } else { s.sourcePriorities.suppressHealthKitCopiesOf.remove(.whoop) }
            try? repo.updateSettings(s)
        }
    }

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false; touch() }
        guard let sync else { return }
        let reports = await sync.syncAll()
        if let failed = reports.first(where: { $0.error != nil && $0.kind != .garminPersonalAPI }) {
            errorMessage = "\(failed.kind.displayName): \(failed.error?.errorDescription ?? "Fehler")"
        }
    }

    func setDevice(_ kind: IntegrationKind, enabled: Bool) {
        var d = repo.device(kind)
        d.isEnabled = enabled
        attempt("Gerät speichern") { try repo.updateDevice(d) }
        rebuildSync()
    }

    func updateDevice(_ d: DeviceConnection) { attempt("Gerät speichern") { try repo.updateDevice(d) }; rebuildSync() }

    func connectAppleHealth() async {
        do {
            try await health.requestAuthorization(write: repo.profile.consents.saveWorkoutsToAppleHealth)
            var p = repo.profile; p.consents.readAppleHealth = true; updateProfile(p)
            var d = repo.device(.appleHealth); d.isEnabled = true; d.status = .connected; d.connectedAt = Date()
            updateDevice(d)
            var w = repo.device(.appleWatch); w.isEnabled = true; w.status = health.isWatchPaired ? .connected : .unavailable(reason: "Keine gekoppelte Apple Watch erkannt")
            updateDevice(w)
            await syncNow()
        } catch {
            errorMessage = "Apple Health: \(error.localizedDescription)"
        }
    }

    func connectWhoop(config: WhoopConfiguration) async {
        var s = repo.settings
        s.whoop = config
        attempt("WHOOP-Konfiguration speichern") { try repo.updateSettings(s) }
        do {
            let client = WhoopClient(config: config, tokens: tokenStore)
            let token = try await WhoopAuthService().authorize(config: config, client: client)
            var d = repo.device(.whoop)
            d.isEnabled = true; d.status = .connected; d.connectedAt = Date()
            d.grantedScopes = token.scope.split(separator: " ").map(String.init)
            updateDevice(d)
            await syncNow()
        } catch {
            var d = repo.device(.whoop)
            d.status = .error(message: error.localizedDescription, at: Date())
            updateDevice(d)
            errorMessage = "WHOOP: \(error.localizedDescription)"
        }
    }

    /// Widerruf: Verbindung trennen, Token löschen, optional importierte Rohdaten entfernen.
    func revoke(_ kind: IntegrationKind, deleteData: Bool) async {
        if kind == .whoop, let cfg = repo.settings.whoop {
            await WhoopClient(config: cfg, tokens: tokenStore).disconnect()
        }
        var d = repo.device(kind)
        d.isEnabled = false
        d.status = .revoked(at: Date())
        d.grantedScopes = []
        updateDevice(d)
        if deleteData {
            attempt("Daten löschen") { try repo.deleteVitals(from: kind.dataSource, channel: kind == .whoop ? .whoopAPI : .healthKit) }
        }
    }

    func garminAvailability() -> SourceAvailabilityReport { GarminViaHealth.availability(from: vitals) }

    func updatePriorities(_ p: SourcePriorities) {
        var s = repo.settings
        s.sourcePriorities = p
        attempt("Prioritäten speichern") { try repo.updateSettings(s) }
    }

    func updateSettings(_ s: AppSettings) { attempt("Einstellungen speichern") { try repo.updateSettings(s) } }

    // MARK: Datenschutz

    func exportFiles() throws -> [URL] {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(Int(Date().timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exporter = DataExporter()
        let json = dir.appendingPathComponent("kettlebell-trx-export.json")
        try exporter.json(from: repo).write(to: json, options: [.atomic, .completeFileProtection])
        let sets = dir.appendingPathComponent("saetze.csv")
        try Data(exporter.setsCSV(sessions: repo.sessions, library: library).utf8).write(to: sets, options: [.atomic, .completeFileProtection])
        let vit = dir.appendingPathComponent("vitaldaten.csv")
        try Data(exporter.vitalsCSV(repo.vitals).utf8).write(to: vit, options: [.atomic, .completeFileProtection])
        return [json, sets, vit]
    }

    func loadDemoData() {
        guard let plan = repo.plan else { return }
        attempt("Beispieldaten laden") {
            for s in DemoDataGenerator().sessions(plan: plan, upTo: Date()) { try repo.upsertSession(s) }
            try repo.ingestVitals(DemoDataGenerator().vitals(days: 60, endingAt: Date()))
        }
    }

    func deleteDemoData() { attempt("Beispieldaten löschen") { try repo.deleteDemoData() } }

    func deleteAllData() async {
        for k in [IntegrationKind.whoop] where repo.device(k).isEnabled { await revoke(k, deleteData: false) }
        try? tokenStore.deleteToken(for: WhoopAuthorization.tokenKey)
        attempt("Alle Daten löschen") { try repo.deleteAllPersonalData() }
        run = nil
        ensurePlan()
        rebuildSync()
    }
}

extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
