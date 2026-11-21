import Foundation

/// Garmin – Integrationsstufe 1: Daten, die Garmin Connect nach Apple Health schreibt.
///
/// Der eigentliche HealthKit-Abruf erfolgt in der iOS-App (`HealthKitVitalProvider`), die
/// Quellenzuordnung über `HealthSourceClassifier` (Bundle-ID `com.garmin.connect…`).
/// Dieser Typ beschreibt die zu prüfenden Datenarten und erstellt den Verfügbarkeitsbericht.
public enum GarminViaHealth {
    /// Datenarten, die laut öffentlichen Angaben von Garmin Connect nach Apple Health
    /// übertragen werden KÖNNEN. Ob sie für die Approach S70 tatsächlich ankommen, zeigt der
    /// Verfügbarkeitsbericht auf dem echten Gerät (Einstellungen → Geräte → Garmin → Prüfen).
    public static let candidateTypes: [VitalType] = [
        .heartRate, .restingHeartRate, .hrvSDNN, .sleepDuration, .sleepDeep, .sleepREM, .sleepLight, .sleepAwake,
        .activeEnergy, .steps, .respiratoryRate, .oxygenSaturation, .workoutDuration,
    ]

    public static func availability(from samples: [VitalSample], now: Date = Date()) -> SourceAvailabilityReport {
        SourceAvailabilityReport.build(source: .garmin, samples: samples, checked: candidateTypes, now: now)
    }
}

/// Garmin – Integrationsstufe 2: direkte Anbindung.
///
/// Status (November 2026): Für Privatpersonen nennt Garmin eine „Personal API“ für den Zugriff
/// auf die eigenen Daten; Details (Authentifizierung, Endpunkte, Limits, Nutzungsbedingungen)
/// konnten in dieser Entwicklungsumgebung NICHT verifiziert werden. Das Garmin Connect
/// Developer Program (Health/Activity API) ist laut Garmin ausschließlich für Unternehmen.
///
/// Gemäß Auftrag wird eine direkte Anbindung erst implementiert, wenn ein Zugang tatsächlich
/// bereitsteht. Bis dahin liefert dieser Adapter ausdrücklich „nicht verfügbar“ – es werden
/// keine inoffiziellen Schnittstellen und kein Zugangsdaten-Scraping verwendet.
public struct GarminDirectProvider: VitalDataProvider {
    public let kind = IntegrationKind.garminPersonalAPI
    public init() {}
    public func fetch(since: Date?, cursor: String?, until: Date) async throws -> ProviderBatch {
        throw ProviderError.unavailable("Direkte Garmin-Anbindung ohne bestätigten API-Zugang nicht aktiviert")
    }
}
