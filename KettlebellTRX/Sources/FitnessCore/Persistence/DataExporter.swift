import Foundation

/// Export persönlicher Daten (DSGVO Art. 20 – Datenübertragbarkeit).
public struct DataExporter: Sendable {
    public struct ExportBundle: Codable, Sendable {
        public var exportedAt: Date
        public var appSchemaVersion: Int
        public var profile: UserProfile
        public var plan: TrainingPlan?
        public var planArchive: [TrainingPlan]
        public var sessions: [WorkoutSession]
        public var vitals: [VitalSample]
        public var recovery: [RecoveryMetric]
        public var painReports: [PainReport]
        public var checkIns: [ReadinessCheckIn]
        public var recommendations: [Recommendation]
        public var devices: [DeviceConnection]
        public var syncStates: [SyncState]
        /// Zugangstoken werden NIE exportiert.
        public var note: String
    }

    public init() {}

    public func bundle(from r: AppRepository, now: Date = Date()) -> ExportBundle {
        ExportBundle(exportedAt: now, appSchemaVersion: AppRepository.currentSchemaVersion, profile: r.profile, plan: r.plan,
                     planArchive: r.planArchive, sessions: r.sessions, vitals: r.vitals, recovery: r.recovery,
                     painReports: r.painReports, checkIns: r.checkIns, recommendations: r.recommendations,
                     devices: r.devices, syncStates: r.syncStates,
                     note: "Export ohne Zugangstoken. Beispieldaten sind mit isDemo bzw. quality=demo gekennzeichnet.")
    }

    public func json(from r: AppRepository, now: Date = Date()) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return try e.encode(bundle(from: r, now: now))
    }

    static func csvField(_ s: String) -> String {
        s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// Satzprotokoll als CSV (Semikolon-getrennt, für deutsches Excel/Numbers).
    public func setsCSV(sessions: [WorkoutSession], library: ExerciseLibrary?) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["Datum;Einheit;Tagestyp;Block;Übung;Satz;Ziel;Ist;Einheit_Ziel;Je_Seite;Gewicht_kg;RPE_Einheit;Beispieldaten"]
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            for ex in s.exercises {
                let name = library?[ex.exerciseId]?.nameDE ?? ex.exerciseId
                for set in ex.sets {
                    lines.append([
                        iso.string(from: set.completedAt), s.id.uuidString, s.dayType.rawValue, ex.block.rawValue,
                        Self.csvField(name), String(set.setIndex + 1), String(set.target), String(set.achieved),
                        set.targetKind == .reps ? "Wdh" : "s", set.perSide ? "ja" : "nein",
                        set.weightKg.map { String(format: "%.1f", $0) } ?? "",
                        s.feedback.map { String($0.rpe) } ?? "", s.isDemo ? "ja" : "nein",
                    ].joined(separator: ";"))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public func vitalsCSV(_ vitals: [VitalSample]) -> String {
        let iso = ISO8601DateFormatter()
        var lines = ["Typ;Wert;Einheit;Beginn;Ende;Quelle;Kanal;Gerät;Qualität;Trainingseinheit"]
        for v in vitals.sorted(by: { $0.start < $1.start }) {
            lines.append([v.type.rawValue, String(v.value), v.unit.rawValue, iso.string(from: v.start),
                          v.end.map { iso.string(from: $0) } ?? "", v.source.rawValue, v.channel.rawValue,
                          Self.csvField(v.deviceId ?? ""), v.quality.rawValue, v.sessionId?.uuidString ?? ""].joined(separator: ";"))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
