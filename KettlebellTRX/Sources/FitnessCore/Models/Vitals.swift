import Foundation

/// Ursprüngliche Datenquelle (das messende System).
public enum DataSource: String, Codable, CaseIterable, Sendable, Hashable {
    case appleWatch, iPhone, garmin, whoop, app, manual, otherHealthApp

    public var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch"
        case .iPhone: return "iPhone"
        case .garmin: return "Garmin"
        case .whoop: return "WHOOP"
        case .app: return "Diese App"
        case .manual: return "Manuelle Eingabe"
        case .otherHealthApp: return "Andere Health-App"
        }
    }
}

/// Übertragungsweg, über den ein Wert in die App gelangt ist.
public enum DataChannel: String, Codable, CaseIterable, Sendable, Hashable {
    case watchLive        // Live-Workout auf der Apple Watch (Mirroring/WatchConnectivity)
    case healthKit        // aus Apple Health gelesen
    case whoopAPI         // offizielle WHOOP API v2
    case garminAPI        // direkte Garmin-Schnittstelle (nur mit bestätigtem Zugang)
    case userInput
    case demo
}

public enum VitalType: String, Codable, CaseIterable, Sendable, Hashable {
    case heartRate, restingHeartRate
    /// HRV als SDNN (Apple Health / Apple Watch).
    case hrvSDNN
    /// HRV als RMSSD (WHOOP). Wird NIE mit SDNN vermischt.
    case hrvRMSSD
    case sleepDuration, sleepDeep, sleepREM, sleepLight, sleepAwake
    case activeEnergy, steps
    case recoveryScore, strain
    case respiratoryRate, oxygenSaturation
    case workoutDuration, perceivedExertion

    public var unit: VitalUnit {
        switch self {
        case .heartRate, .restingHeartRate: return .bpm
        case .hrvSDNN, .hrvRMSSD: return .milliseconds
        case .sleepDuration, .sleepDeep, .sleepREM, .sleepLight, .sleepAwake, .workoutDuration: return .minutes
        case .activeEnergy: return .kilocalories
        case .steps: return .count
        case .recoveryScore, .oxygenSaturation: return .percent
        case .strain: return .score
        case .respiratoryRate: return .breathsPerMinute
        case .perceivedExertion: return .score
        }
    }

    public var displayName: String {
        switch self {
        case .heartRate: return "Herzfrequenz"
        case .restingHeartRate: return "Ruhepuls"
        case .hrvSDNN: return "HRV (SDNN)"
        case .hrvRMSSD: return "HRV (RMSSD)"
        case .sleepDuration: return "Schlafdauer"
        case .sleepDeep: return "Tiefschlaf"
        case .sleepREM: return "REM-Schlaf"
        case .sleepLight: return "Leichtschlaf"
        case .sleepAwake: return "Wachphasen"
        case .activeEnergy: return "Aktiver Energieverbrauch (geschätzt)"
        case .steps: return "Schritte"
        case .recoveryScore: return "Recovery Score"
        case .strain: return "Belastung (Strain)"
        case .respiratoryRate: return "Atemfrequenz"
        case .oxygenSaturation: return "Sauerstoffsättigung"
        case .workoutDuration: return "Trainingsdauer"
        case .perceivedExertion: return "Subjektive Belastung (RPE)"
        }
    }

    /// Messmethode, falls für die Vergleichbarkeit relevant.
    public var method: String? {
        switch self {
        case .hrvSDNN: return "SDNN"
        case .hrvRMSSD: return "RMSSD"
        default: return nil
        }
    }

    /// Typen, die als Tageswert verdichtet werden (statt Zeitreihe).
    public var isDailyMetric: Bool {
        switch self {
        case .heartRate, .activeEnergy, .steps, .workoutDuration, .perceivedExertion: return false
        default: return true
        }
    }
}

public enum VitalUnit: String, Codable, Sendable {
    case bpm, milliseconds, minutes, kilocalories, count, percent, score, breathsPerMinute
    public var symbol: String {
        switch self {
        case .bpm: return "S/min"
        case .milliseconds: return "ms"
        case .minutes: return "min"
        case .kilocalories: return "kcal"
        case .count: return ""
        case .percent: return "%"
        case .score: return ""
        case .breathsPerMinute: return "/min"
        }
    }
}

public enum MeasurementQuality: String, Codable, Sendable {
    case measured          // direkt vom Sensor
    case derived           // von der Quelle berechnet (z. B. Recovery Score, Schlafphasen)
    case estimated         // Schätzung (z. B. Energieverbrauch) – wird so gekennzeichnet
    case userEntered
    case calibrating       // Quelle meldet Kalibrierungsphase (z. B. WHOOP user_calibrating)
    case unscored          // Quelle hat keinen Wert berechnet
    case demo              // ausdrücklich gekennzeichnete Beispieldaten
}

/// Geräteunabhängiger Vitaldatensatz. Rohdaten bleiben unverändert erhalten.
public struct VitalSample: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var type: VitalType
    public var value: Double
    public var unit: VitalUnit
    public var start: Date
    public var end: Date?
    public var source: DataSource
    public var channel: DataChannel
    public var deviceId: String?
    /// ID des Datensatzes im Ursprungssystem (HealthKit-UUID, WHOOP-ID …) für die Duplikaterkennung.
    public var sourceRecordId: String?
    public var sessionId: UUID?
    public var quality: MeasurementQuality
    public var importedAt: Date

    public init(id: UUID = UUID(), type: VitalType, value: Double, unit: VitalUnit? = nil, start: Date, end: Date? = nil,
                source: DataSource, channel: DataChannel, deviceId: String? = nil, sourceRecordId: String? = nil,
                sessionId: UUID? = nil, quality: MeasurementQuality = .measured, importedAt: Date = Date()) {
        self.id = id; self.type = type; self.value = value; self.unit = unit ?? type.unit; self.start = start
        self.end = end; self.source = source; self.channel = channel; self.deviceId = deviceId
        self.sourceRecordId = sourceRecordId; self.sessionId = sessionId; self.quality = quality
        self.importedAt = importedAt
    }

    public var method: String? { type.method }
}

/// Tageszusammenfassung der Regeneration je Quelle (nicht quellenübergreifend gemischt).
public struct RecoveryMetric: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(source.rawValue)-\(dayKey)" }
    public var dayKey: String          // yyyy-MM-dd (Aufwachtag)
    public var source: DataSource
    public var recoveryScore: Double?
    public var hrvMs: Double?
    public var hrvMethod: String?
    public var restingHeartRate: Double?
    public var sleepMinutes: Double?
    public var deepSleepMinutes: Double?
    public var remSleepMinutes: Double?
    public var lightSleepMinutes: Double?
    public var awakeMinutes: Double?
    public var strain: Double?
    public var quality: MeasurementQuality

    public init(dayKey: String, source: DataSource, recoveryScore: Double? = nil, hrvMs: Double? = nil, hrvMethod: String? = nil,
                restingHeartRate: Double? = nil, sleepMinutes: Double? = nil, deepSleepMinutes: Double? = nil,
                remSleepMinutes: Double? = nil, lightSleepMinutes: Double? = nil, awakeMinutes: Double? = nil,
                strain: Double? = nil, quality: MeasurementQuality) {
        self.dayKey = dayKey; self.source = source; self.recoveryScore = recoveryScore; self.hrvMs = hrvMs
        self.hrvMethod = hrvMethod; self.restingHeartRate = restingHeartRate; self.sleepMinutes = sleepMinutes
        self.deepSleepMinutes = deepSleepMinutes; self.remSleepMinutes = remSleepMinutes
        self.lightSleepMinutes = lightSleepMinutes; self.awakeMinutes = awakeMinutes; self.strain = strain
        self.quality = quality
    }
}

public enum DayKey {
    public static func string(for date: Date, calendar: Calendar = .iso8601Monday) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func date(from key: String, calendar: Calendar = .iso8601Monday) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
