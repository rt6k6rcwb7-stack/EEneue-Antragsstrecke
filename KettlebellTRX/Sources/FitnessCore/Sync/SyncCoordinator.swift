import Foundation

/// Ergebnis eines Abrufs bei einer externen Quelle.
public struct ProviderBatch: Sendable {
    public var samples: [VitalSample]
    /// Neuer Cursor (z. B. HealthKit-Anchor), wird erst nach erfolgreicher Speicherung übernommen.
    public var cursor: String?
    public var syncedUntil: Date
    public init(samples: [VitalSample], cursor: String? = nil, syncedUntil: Date) {
        self.samples = samples; self.cursor = cursor; self.syncedUntil = syncedUntil
    }
}

public enum ProviderError: Error, LocalizedError, Sendable, Equatable {
    case notAuthorized
    case notConfigured(String)
    case network(String)
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case decoding(String)
    case unavailable(String)

    public var isRecoverable: Bool {
        switch self {
        case .network, .rateLimited, .server: return true
        default: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Nicht autorisiert – bitte Verbindung erneut herstellen."
        case .notConfigured(let m): return "Nicht eingerichtet: \(m)"
        case .network(let m): return "Netzwerkfehler: \(m)"
        case .rateLimited: return "Zu viele Anfragen – später erneut versuchen."
        case .server(let s): return "Serverfehler (\(s))."
        case .decoding(let m): return "Unerwartetes Datenformat: \(m)"
        case .unavailable(let m): return "Nicht verfügbar: \(m)"
        }
    }
}

/// Einheitliche Schnittstelle aller Vitaldaten-Adapter (HealthKit, Garmin, WHOOP …).
public protocol VitalDataProvider: Sendable {
    var kind: IntegrationKind { get }
    func fetch(since: Date?, cursor: String?, until: Date) async throws -> ProviderBatch
}

public struct SyncReport: Sendable {
    public var kind: IntegrationKind
    public var result: IngestResult?
    public var error: ProviderError?
}

/// Führt die Synchronisierung aller aktivierten Quellen durch.
/// Fehler einer Quelle beeinflussen weder andere Quellen noch lokal gespeicherte Trainingsdaten.
public final class SyncCoordinator: @unchecked Sendable {
    public let repository: AppRepository
    public var providers: [IntegrationKind: VitalDataProvider]
    /// Erster Abruf: so weit zurück (Tage).
    public var initialLookbackDays = 30
    /// Überlappung, damit spät eintreffende Daten nicht verloren gehen (Duplikate werden erkannt).
    public var overlap: TimeInterval = 36 * 3600

    public init(repository: AppRepository, providers: [VitalDataProvider]) {
        self.repository = repository
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.kind, $0) })
    }

    public func syncAll(now: Date = Date()) async -> [SyncReport] {
        var reports: [SyncReport] = []
        for kind in IntegrationKind.allCases {
            guard let p = providers[kind], repository.device(kind).isEnabled else { continue }
            reports.append(await sync(p, now: now))
        }
        return reports
    }

    public func sync(_ provider: VitalDataProvider, now: Date = Date()) async -> SyncReport {
        var state = repository.syncState(provider.kind)
        state.lastAttempt = now
        let since = state.syncedUntil.map { $0.addingTimeInterval(-overlap) }
            ?? now.addingTimeInterval(-Double(initialLookbackDays) * 86400)
        do {
            let batch = try await provider.fetch(since: since, cursor: state.cursor, until: now)
            let result = try repository.ingestVitals(batch.samples)
            state.cursor = batch.cursor ?? state.cursor
            state.syncedUntil = batch.syncedUntil
            state.lastSuccess = now
            state.lastError = nil
            state.consecutiveFailures = 0
            state.lastImportedCount = result.inserted
            try? repository.updateSyncState(state)
            var device = repository.device(provider.kind)
            if case .connected = device.status {} else {
                device.status = .connected
                try? repository.updateDevice(device)
            }
            return SyncReport(kind: provider.kind, result: result, error: nil)
        } catch {
            let pe = (error as? ProviderError) ?? .network(error.localizedDescription)
            state.lastError = SyncError(message: pe.errorDescription ?? "Unbekannter Fehler", at: now, isRecoverable: pe.isRecoverable)
            state.consecutiveFailures += 1
            try? repository.updateSyncState(state)
            if pe == .notAuthorized {
                var device = repository.device(provider.kind)
                device.status = .error(message: pe.errorDescription ?? "", at: now)
                try? repository.updateDevice(device)
            }
            return SyncReport(kind: provider.kind, result: nil, error: pe)
        }
    }

    /// Exponentielles Backoff für automatische Wiederholungen (max. 6 h).
    public static func retryDelay(afterFailures n: Int) -> TimeInterval {
        min(6 * 3600, 60 * pow(2, Double(max(0, n - 1))))
    }
}
