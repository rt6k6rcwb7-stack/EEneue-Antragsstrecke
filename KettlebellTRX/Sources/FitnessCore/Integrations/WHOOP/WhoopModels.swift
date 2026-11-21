import Foundation

/// Datenstrukturen der WHOOP Developer API v2 (nur die benötigten Felder).
/// Referenz: https://developer.whoop.com/api – Felder vor Produktivnutzung gegen die
/// aktuelle Dokumentation prüfen (siehe Docs/INTEGRATIONS.md).
public enum WhoopScoreState: String, Codable, Sendable {
    case scored = "SCORED"
    case pendingScore = "PENDING_SCORE"
    case unscorable = "UNSCORABLE"
}

public struct WhoopPage<T: Decodable & Sendable>: Decodable, Sendable {
    public var records: [T]
    public var nextToken: String?
    enum CodingKeys: String, CodingKey { case records, nextToken = "next_token" }
}

public struct WhoopRecovery: Decodable, Sendable {
    public struct Score: Decodable, Sendable {
        public var userCalibrating: Bool?
        public var recoveryScore: Double?
        public var restingHeartRate: Double?
        public var hrvRmssdMilli: Double?
        public var spo2Percentage: Double?
        public var skinTempCelsius: Double?
        enum CodingKeys: String, CodingKey {
            case userCalibrating = "user_calibrating", recoveryScore = "recovery_score"
            case restingHeartRate = "resting_heart_rate", hrvRmssdMilli = "hrv_rmssd_milli"
            case spo2Percentage = "spo2_percentage", skinTempCelsius = "skin_temp_celsius"
        }
    }
    public var cycleId: Int64?
    public var sleepId: String?
    public var createdAt: Date
    public var updatedAt: Date?
    public var scoreState: WhoopScoreState
    public var score: Score?
    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id", sleepId = "sleep_id", createdAt = "created_at", updatedAt = "updated_at"
        case scoreState = "score_state", score
    }
}

public struct WhoopSleep: Decodable, Sendable {
    public struct StageSummary: Decodable, Sendable {
        public var totalInBedTimeMilli: Double?
        public var totalAwakeTimeMilli: Double?
        public var totalNoDataTimeMilli: Double?
        public var totalLightSleepTimeMilli: Double?
        public var totalSlowWaveSleepTimeMilli: Double?
        public var totalRemSleepTimeMilli: Double?
        enum CodingKeys: String, CodingKey {
            case totalInBedTimeMilli = "total_in_bed_time_milli", totalAwakeTimeMilli = "total_awake_time_milli"
            case totalNoDataTimeMilli = "total_no_data_time_milli", totalLightSleepTimeMilli = "total_light_sleep_time_milli"
            case totalSlowWaveSleepTimeMilli = "total_slow_wave_sleep_time_milli", totalRemSleepTimeMilli = "total_rem_sleep_time_milli"
        }
    }
    public struct Score: Decodable, Sendable {
        public var stageSummary: StageSummary?
        public var respiratoryRate: Double?
        public var sleepPerformancePercentage: Double?
        enum CodingKeys: String, CodingKey {
            case stageSummary = "stage_summary", respiratoryRate = "respiratory_rate"
            case sleepPerformancePercentage = "sleep_performance_percentage"
        }
    }
    public var id: String
    public var start: Date
    public var end: Date
    public var nap: Bool
    public var scoreState: WhoopScoreState
    public var score: Score?
    enum CodingKeys: String, CodingKey { case id, start, end, nap, scoreState = "score_state", score }
}

public struct WhoopCycle: Decodable, Sendable {
    public struct Score: Decodable, Sendable {
        public var strain: Double?
        public var kilojoule: Double?
        public var averageHeartRate: Double?
        public var maxHeartRate: Double?
        enum CodingKeys: String, CodingKey {
            case strain, kilojoule, averageHeartRate = "average_heart_rate", maxHeartRate = "max_heart_rate"
        }
    }
    public var id: Int64
    public var start: Date
    public var end: Date?
    public var scoreState: WhoopScoreState
    public var score: Score?
    enum CodingKeys: String, CodingKey { case id, start, end, scoreState = "score_state", score }
}

public struct WhoopWorkout: Decodable, Sendable {
    public struct Score: Decodable, Sendable {
        public var strain: Double?
        public var averageHeartRate: Double?
        public var maxHeartRate: Double?
        enum CodingKeys: String, CodingKey { case strain, averageHeartRate = "average_heart_rate", maxHeartRate = "max_heart_rate" }
    }
    public var id: String
    public var start: Date
    public var end: Date
    public var sportName: String?
    public var scoreState: WhoopScoreState
    public var score: Score?
    enum CodingKeys: String, CodingKey { case id, start, end, sportName = "sport_name", scoreState = "score_state", score }
}

public struct WhoopTokenResponse: Decodable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresIn: Double
    public var scope: String?
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", scope
    }
    public func token(issuedAt now: Date) -> OAuthToken {
        OAuthToken(accessToken: accessToken, refreshToken: refreshToken, expiresAt: now.addingTimeInterval(expiresIn), scope: scope ?? "")
    }
}

enum WhoopDate {
    /// WHOOP liefert ISO-8601 mit Millisekunden („2025-07-01T06:12:00.123Z“).
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter(); f2.formatOptions = [.withInternetDateTime]
            if let d = f1.date(from: s) ?? f2.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "Ungültiges Datum \(s)"))
        }
        return d
    }()
}
