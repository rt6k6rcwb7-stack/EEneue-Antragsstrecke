import Foundation

/// Dateinamen der Sammlungen.
public enum StoreFile: String, CaseIterable, Sendable {
    case meta, profile, plan, planArchive, sessions, vitals, recovery, devices, syncStates
    case painReports, checkIns, recommendations, settings, activeRun
}

public struct StoreMeta: Codable, Sendable { public var schemaVersion: Int; public var createdAt: Date }

public struct AppSettings: Codable, Hashable, Sendable {
    public var sourcePriorities: SourcePriorities = .standard
    public var restTimerSound: Bool = true
    public var restTimerHaptics: Bool = true
    public var keepScreenOnDuringWorkout: Bool = true
    /// Öffentliche WHOOP-App-Daten (Client-ID, Redirect, eigener Token-Broker). Kein Secret.
    public var whoop: WhoopConfiguration?
    public init() {}
}

/// Schema-Migration. Neue App-Versionen registrieren Migrationen in `AppRepository.migrations`.
public struct SchemaMigration: Sendable {
    public var fromVersion: Int
    public var description: String
    public var migrate: @Sendable (LocalStore) throws -> Void
    public init(fromVersion: Int, description: String, migrate: @escaping @Sendable (LocalStore) throws -> Void) {
        self.fromVersion = fromVersion; self.description = description; self.migrate = migrate
    }
}

public enum MigrationError: Error, LocalizedError {
    case newerSchema(found: Int, supported: Int)
    case missingMigration(from: Int)
    public var errorDescription: String? {
        switch self {
        case .newerSchema(let f, let s): return "Die Daten stammen aus einer neueren App-Version (Schema \(f), unterstützt \(s))."
        case .missingMigration(let v): return "Keine Migration für Schema-Version \(v) vorhanden."
        }
    }
}

/// Zentrale lokale Datenhaltung. Hält den Zustand im Speicher (mit Indizes) und schreibt
/// jede Änderung sofort auf das Gerät.
public final class AppRepository: @unchecked Sendable {
    public static let currentSchemaVersion = 1

    public let store: LocalStore
    public private(set) var profile: UserProfile
    public private(set) var plan: TrainingPlan?
    public private(set) var planArchive: [TrainingPlan] = []
    public private(set) var sessions: [WorkoutSession] = []
    public private(set) var vitals: [VitalSample] = []
    public private(set) var recovery: [RecoveryMetric] = []
    public private(set) var devices: [DeviceConnection] = DeviceConnection.defaults()
    public private(set) var syncStates: [SyncState] = []
    public private(set) var painReports: [PainReport] = []
    public private(set) var checkIns: [ReadinessCheckIn] = []
    public private(set) var recommendations: [Recommendation] = []
    public private(set) var settings = AppSettings()
    public private(set) var activeRun: WorkoutRun?
    /// `false`, solange die Person den Einrichtungsassistenten noch nicht abgeschlossen hat.
    public private(set) var hasStoredProfile = false

    private var sessionIndex: [UUID: Int] = [:]

    public init(store: LocalStore, migrations: [SchemaMigration] = []) throws {
        self.store = store
        try Self.migrateIfNeeded(store: store, migrations: migrations)
        let storedProfile = try store.load(UserProfile.self, from: StoreFile.profile.rawValue)
        hasStoredProfile = storedProfile != nil
        profile = storedProfile ?? .initial()
        plan = try store.load(TrainingPlan.self, from: StoreFile.plan.rawValue)
        planArchive = try store.load([TrainingPlan].self, from: StoreFile.planArchive.rawValue) ?? []
        sessions = try store.load([WorkoutSession].self, from: StoreFile.sessions.rawValue) ?? []
        vitals = try store.load([VitalSample].self, from: StoreFile.vitals.rawValue) ?? []
        recovery = try store.load([RecoveryMetric].self, from: StoreFile.recovery.rawValue) ?? []
        devices = mergeDefaults(try store.load([DeviceConnection].self, from: StoreFile.devices.rawValue) ?? [])
        syncStates = try store.load([SyncState].self, from: StoreFile.syncStates.rawValue) ?? []
        painReports = try store.load([PainReport].self, from: StoreFile.painReports.rawValue) ?? []
        checkIns = try store.load([ReadinessCheckIn].self, from: StoreFile.checkIns.rawValue) ?? []
        recommendations = try store.load([Recommendation].self, from: StoreFile.recommendations.rawValue) ?? []
        settings = try store.load(AppSettings.self, from: StoreFile.settings.rawValue) ?? AppSettings()
        activeRun = try store.load(WorkoutRun.self, from: StoreFile.activeRun.rawValue)
        rebuildIndex()
        if try store.load(StoreMeta.self, from: StoreFile.meta.rawValue) == nil {
            try store.save(StoreMeta(schemaVersion: Self.currentSchemaVersion, createdAt: Date()), as: StoreFile.meta.rawValue)
        }
    }

    static func migrateIfNeeded(store: LocalStore, migrations: [SchemaMigration]) throws {
        guard var meta = try store.load(StoreMeta.self, from: StoreFile.meta.rawValue) else { return }
        if meta.schemaVersion > currentSchemaVersion {
            throw MigrationError.newerSchema(found: meta.schemaVersion, supported: currentSchemaVersion)
        }
        while meta.schemaVersion < currentSchemaVersion {
            guard let m = migrations.first(where: { $0.fromVersion == meta.schemaVersion }) else {
                throw MigrationError.missingMigration(from: meta.schemaVersion)
            }
            try m.migrate(store)
            meta.schemaVersion += 1
            try store.save(meta, as: StoreFile.meta.rawValue)
        }
    }

    private func mergeDefaults(_ stored: [DeviceConnection]) -> [DeviceConnection] {
        DeviceConnection.defaults().map { d in stored.first { $0.kind == d.kind } ?? d }
    }

    private func rebuildIndex() {
        sessionIndex = Dictionary(uniqueKeysWithValues: sessions.enumerated().map { ($1.id, $0) })
    }

    // MARK: Profil & Plan

    public func updateProfile(_ p: UserProfile) throws {
        var p = p
        p.updatedAt = Date()
        profile = p
        try store.save(profile, as: StoreFile.profile.rawValue)
        hasStoredProfile = true
    }

    /// Abschluss des Einrichtungsassistenten: Profil speichern und ersten Plan anlegen.
    public func completeOnboarding(profile p: UserProfile, library: ExerciseLibrary, startDate: Date) throws {
        try updateProfile(p)
        try setPlan(PlanGenerator(library: library, profile: p).generate(startDate: startDate), archiveCurrent: false)
    }

    public func setPlan(_ p: TrainingPlan, archiveCurrent: Bool = true) throws {
        if archiveCurrent, let old = plan, old.id != p.id {
            planArchive.append(old)
            try store.save(planArchive, as: StoreFile.planArchive.rawValue)
        }
        plan = p
        try store.save(p, as: StoreFile.plan.rawValue)
    }

    public func updatePlannedWorkout(_ w: PlannedWorkout) throws {
        guard var p = plan else { return }
        p.updateWorkout(w)
        try setPlan(p, archiveCurrent: false)
    }

    // MARK: Trainingseinheiten

    public func upsertSession(_ s: WorkoutSession) throws {
        if let i = sessionIndex[s.id] { sessions[i] = s } else {
            sessions.append(s)
            sessionIndex[s.id] = sessions.count - 1
        }
        try store.save(sessions, as: StoreFile.sessions.rawValue)
    }

    public func session(id: UUID) -> WorkoutSession? { sessionIndex[id].map { sessions[$0] } }

    public func deleteSession(id: UUID) throws {
        sessions.removeAll { $0.id == id }
        rebuildIndex()
        try store.save(sessions, as: StoreFile.sessions.rawValue)
    }

    /// Speichert den laufenden Trainingszustand (nach jeder Aktion aufrufen).
    public func saveActiveRun(_ run: WorkoutRun?) throws {
        activeRun = run
        if let run { try store.save(run, as: StoreFile.activeRun.rawValue) } else { store.remove(StoreFile.activeRun.rawValue) }
    }

    /// Schließt ein Training ab: Einheit speichern, Plan markieren, laufenden Zustand entfernen.
    public func completeRun(_ run: WorkoutRun) throws {
        try upsertSession(run.session)
        if let pid = run.session.plannedWorkoutId, var w = plan?.workout(id: pid), run.session.state == .completed {
            w.completedSessionId = run.session.id
            try updatePlannedWorkout(w)
        }
        try saveActiveRun(nil)
        // Herzfrequenzverlauf als Rohdaten erhalten
        let samples = run.heartRate.points.map {
            VitalSample(type: .heartRate, value: $0.bpm, start: $0.date, source: run.heartRate.source ?? .appleWatch,
                        channel: .watchLive, sessionId: run.session.id)
        }
        _ = try ingestVitals(samples)
    }

    // MARK: Vitaldaten

    @discardableResult
    public func ingestVitals(_ samples: [VitalSample]) throws -> IngestResult {
        let h = VitalHarmonizer(priorities: settings.sourcePriorities)
        var copy = vitals
        let r = h.ingest(samples, into: &copy)
        if r.inserted > 0 {
            vitals = copy
            try store.save(vitals, as: StoreFile.vitals.rawValue)
            try refreshRecovery(days: Set(samples.map { DayKey.string(for: $0.end ?? $0.start) }), harmonizer: h)
        }
        return r
    }

    private func refreshRecovery(days: Set<String>, harmonizer: VitalHarmonizer) throws {
        guard !days.isEmpty else { return }
        recovery.removeAll { days.contains($0.dayKey) }
        for d in days { recovery += harmonizer.recoveryMetrics(dayKey: d, in: vitals) }
        recovery.sort { ($0.dayKey, $0.source.rawValue) < ($1.dayKey, $1.source.rawValue) }
        try store.save(recovery, as: StoreFile.recovery.rawValue)
    }

    /// Entfernt alle Rohdaten einer Quelle (z. B. nach Widerruf einer Verbindung).
    public func deleteVitals(from source: DataSource, channel: DataChannel? = nil) throws {
        vitals.removeAll { $0.source == source && (channel == nil || $0.channel == channel) }
        recovery.removeAll { $0.source == source }
        try store.save(vitals, as: StoreFile.vitals.rawValue)
        try store.save(recovery, as: StoreFile.recovery.rawValue)
    }

    // MARK: Geräte & Synchronisierung

    public func updateDevice(_ d: DeviceConnection) throws {
        if let i = devices.firstIndex(where: { $0.kind == d.kind }) { devices[i] = d } else { devices.append(d) }
        try store.save(devices, as: StoreFile.devices.rawValue)
    }

    public func device(_ kind: IntegrationKind) -> DeviceConnection {
        devices.first { $0.kind == kind } ?? DeviceConnection(kind: kind)
    }

    public func syncState(_ kind: IntegrationKind) -> SyncState {
        syncStates.first { $0.kind == kind } ?? SyncState(kind: kind)
    }

    public func updateSyncState(_ s: SyncState) throws {
        if let i = syncStates.firstIndex(where: { $0.kind == s.kind }) { syncStates[i] = s } else { syncStates.append(s) }
        try store.save(syncStates, as: StoreFile.syncStates.rawValue)
    }

    // MARK: Gesundheit & Assistent

    public func addPainReport(_ p: PainReport) throws {
        painReports.append(p)
        try store.save(painReports, as: StoreFile.painReports.rawValue)
    }

    public func deletePainReport(id: UUID) throws {
        painReports.removeAll { $0.id == id }
        try store.save(painReports, as: StoreFile.painReports.rawValue)
    }

    public func addCheckIn(_ c: ReadinessCheckIn) throws {
        checkIns.append(c)
        try store.save(checkIns, as: StoreFile.checkIns.rawValue)
    }

    public func addRecommendation(_ r: Recommendation) throws {
        recommendations.append(r)
        if recommendations.count > 500 { recommendations.removeFirst(recommendations.count - 500) }
        try store.save(recommendations, as: StoreFile.recommendations.rawValue)
    }

    public func updateSettings(_ s: AppSettings) throws {
        settings = s
        try store.save(s, as: StoreFile.settings.rawValue)
    }

    // MARK: Beispieldaten & Löschung

    public var hasDemoData: Bool { sessions.contains(where: \.isDemo) || vitals.contains { $0.quality == .demo } }

    /// Lädt gekennzeichnete Beispiel-Einheiten und markiert die zugehörigen Plantage als erledigt
    /// (nur Tage, die noch keine echte Einheit haben).
    public func loadDemoSessions(_ demo: [WorkoutSession]) throws {
        guard var p = plan else { return }
        for s in demo where s.isDemo {
            try upsertSession(s)
            if let pid = s.plannedWorkoutId, var w = p.workout(id: pid), w.completedSessionId == nil, s.state == .completed {
                w.completedSessionId = s.id
                p.updateWorkout(w)
            }
        }
        try setPlan(p, archiveCurrent: false)
    }

    public func deleteDemoData() throws {
        let demoIds = Set(sessions.filter(\.isDemo).map(\.id))
        sessions.removeAll(where: \.isDemo)
        rebuildIndex()
        // Plan-Markierungen der Beispiel-Einheiten zurücknehmen
        if var p = plan {
            for w in p.allWorkouts where w.completedSessionId.map(demoIds.contains) == true {
                var c = w; c.completedSessionId = nil; p.updateWorkout(c)
            }
            try setPlan(p, archiveCurrent: false)
        }
        vitals.removeAll { $0.quality == .demo || $0.channel == .demo }
        recovery.removeAll { $0.quality == .demo }
        try store.save(sessions, as: StoreFile.sessions.rawValue)
        try store.save(vitals, as: StoreFile.vitals.rawValue)
        try store.save(recovery, as: StoreFile.recovery.rawValue)
    }

    /// Löscht alle personenbezogenen Daten (Profil wird auf den Ausgangszustand zurückgesetzt).
    public func deleteAllPersonalData() throws {
        try store.removeAll()
        profile = .initial(); plan = nil; planArchive = []; sessions = []; vitals = []; recovery = []
        devices = DeviceConnection.defaults(); syncStates = []; painReports = []; checkIns = []
        recommendations = []; settings = AppSettings(); activeRun = nil
        hasStoredProfile = false
        rebuildIndex()
        try store.save(StoreMeta(schemaVersion: Self.currentSchemaVersion, createdAt: Date()), as: StoreFile.meta.rawValue)
    }
}
