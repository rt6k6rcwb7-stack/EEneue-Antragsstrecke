import Foundation

public enum IntegrationKind: String, Codable, CaseIterable, Sendable, Hashable {
    case appleWatch          // Live-Puls via Workout Mirroring
    case appleHealth         // Lesen/Schreiben HealthKit
    case garminViaHealth     // Garmin Connect → Apple Health → App
    case garminPersonalAPI   // direkte Anbindung – nur bei bestätigtem Zugang
    case whoop               // WHOOP API v2 (OAuth 2.0)

    public var displayName: String {
        switch self {
        case .appleWatch: return "Apple Watch (Live-Puls)"
        case .appleHealth: return "Apple Health"
        case .garminViaHealth: return "Garmin über Apple Health"
        case .garminPersonalAPI: return "Garmin direkt (API)"
        case .whoop: return "WHOOP"
        }
    }

    public var dataSource: DataSource {
        switch self {
        case .appleWatch: return .appleWatch
        case .appleHealth: return .iPhone
        case .garminViaHealth, .garminPersonalAPI: return .garmin
        case .whoop: return .whoop
        }
    }
}

public enum ConnectionStatus: Codable, Hashable, Sendable {
    case notConfigured
    case connected
    case unavailable(reason: String)   // z. B. kein API-Zugang, Gerät nicht vorhanden
    case error(message: String, at: Date)
    case revoked(at: Date)

    public var isUsable: Bool { if case .connected = self { return true }; return false }

    public var displayText: String {
        switch self {
        case .notConfigured: return "Nicht eingerichtet"
        case .connected: return "Verbunden"
        case .unavailable(let r): return "Nicht verfügbar: \(r)"
        case .error(let m, _): return "Fehler: \(m)"
        case .revoked: return "Verbindung widerrufen"
        }
    }
}

public struct DeviceConnection: Codable, Identifiable, Hashable, Sendable {
    public var id: IntegrationKind { kind }
    public var kind: IntegrationKind
    public var isEnabled: Bool
    public var status: ConnectionStatus
    public var grantedScopes: [String]
    public var connectedAt: Date?
    public var deviceName: String?

    public init(kind: IntegrationKind, isEnabled: Bool = false, status: ConnectionStatus = .notConfigured,
                grantedScopes: [String] = [], connectedAt: Date? = nil, deviceName: String? = nil) {
        self.kind = kind; self.isEnabled = isEnabled; self.status = status
        self.grantedScopes = grantedScopes; self.connectedAt = connectedAt; self.deviceName = deviceName
    }

    public static func defaults() -> [DeviceConnection] {
        IntegrationKind.allCases.map { kind in
            kind == .garminPersonalAPI
                ? DeviceConnection(kind: kind, status: .unavailable(reason: "Kein bestätigter API-Zugang hinterlegt"))
                : DeviceConnection(kind: kind)
        }
    }
}

public struct SyncError: Codable, Hashable, Sendable {
    public var message: String
    public var at: Date
    public var isRecoverable: Bool
    public init(message: String, at: Date, isRecoverable: Bool) {
        self.message = message; self.at = at; self.isRecoverable = isRecoverable
    }
}

public struct SyncState: Codable, Identifiable, Hashable, Sendable {
    public var id: IntegrationKind { kind }
    public var kind: IntegrationKind
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    /// Zeitpunkt, bis zu dem Daten vollständig übernommen wurden.
    public var syncedUntil: Date?
    /// Quellenspezifischer Cursor (z. B. HealthKit-Anchor als Base64).
    public var cursor: String?
    public var lastError: SyncError?
    public var consecutiveFailures: Int
    public var lastImportedCount: Int

    public init(kind: IntegrationKind, lastAttempt: Date? = nil, lastSuccess: Date? = nil, syncedUntil: Date? = nil,
                cursor: String? = nil, lastError: SyncError? = nil, consecutiveFailures: Int = 0, lastImportedCount: Int = 0) {
        self.kind = kind; self.lastAttempt = lastAttempt; self.lastSuccess = lastSuccess; self.syncedUntil = syncedUntil
        self.cursor = cursor; self.lastError = lastError; self.consecutiveFailures = consecutiveFailures
        self.lastImportedCount = lastImportedCount
    }
}
