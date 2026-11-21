# Architektur

## Projektstruktur

```
KettlebellTRX/
├── Package.swift                 Swift-Paket „FitnessCore“ (+ CLI kbtrx-plan)
├── project.yml                   XcodeGen-Definition (iOS-App + Watch-App)
├── Sources/FitnessCore/          Plattformunabhängige Fachlogik – ohne UIKit/SwiftUI/HealthKit
│   ├── Models/                   UserProfile, Exercise, TrainingPlan, WorkoutSession, ExerciseSet,
│   │                             VitalSample, RecoveryMetric, DeviceConnection, SyncState …
│   ├── Library/                  ExerciseLibrary + Resources/exercises.json (58 Übungen)
│   ├── Animation/                PoseLibrary: eigene Strichfigur-Animationen (Vorwärtskinematik)
│   ├── Planning/                 PlanGenerator, SafetyFilter, WeightSelector, ProgressionEngine
│   ├── Workout/                  WorkoutRun (Player-Zustandsmaschine), HeartRateSeries
│   ├── Vitals/                   VitalHarmonizer (Duplikate, Prioritäten, Basislinien), VitalAlerts
│   ├── Assistant/                TrainingAssistant (Regeln S/L/V)
│   ├── Analytics/                TrainingAnalytics (Zeiträume, Diagramm-Reihen)
│   ├── Persistence/              LocalStore, AppRepository (Migrationen), DataExporter
│   ├── Sync/                     SyncCoordinator, WatchProtocol (Outbox/Inbox)
│   ├── Integrations/             HTTPClient, OAuthToken/TokenStore, WHOOP, Garmin, HealthKit-Mapping
│   └── Demo/                     gekennzeichnete Beispieldaten
├── Sources/kbtrx-plan/           Kommandozeilen-Vorschau
├── Tests/FitnessCoreTests/       66 Tests
├── Apps/iOS/                     SwiftUI-App (UI, HealthKit, Watch-Brücke, Keychain, WHOOP-OAuth)
├── Apps/watchOS/                 Watch-App (HKWorkoutSession, Mirroring)
├── Backend/whoop-token-broker/   Cloudflare Worker – verwahrt das WHOOP-Client-Secret
├── Tools/generate_exercises.py   Pflegewerkzeug für die Übungsdatei
└── Docs/
```

## Komponenten und Schichten

| # | Bereich (Auftrag) | Umsetzung |
|---|---|---|
| 1 | Benutzeroberfläche | `Apps/iOS/Views`, `Apps/watchOS` – nur Darstellung und Weiterleitung an `AppModel` |
| 2 | Trainingslogik | `Planning/*`, `Workout/WorkoutRun` |
| 3 | Übungsdatenbank | `Library/ExerciseLibrary` + `exercises.json` |
| 4 | Trainingshistorie | `AppRepository.sessions`, `WorkoutSession`/`ExerciseSet` |
| 5 | Vitaldatenverwaltung | `VitalSample`, `VitalHarmonizer`, `RecoveryMetric` |
| 6 | Geräteintegration | `Integrations/*`, `Apps/iOS/Services/*`, `Apps/watchOS/WatchWorkoutManager` |
| 7 | Synchronisierung | `SyncCoordinator`, `VitalDataProvider`, `WatchProtocol` |
| 8 | Trainingsanalyse | `TrainingAnalytics`, `TrainingAssistant`, `ProgressionEngine` |
| 9 | Datenschutz & Berechtigungen | `LocalStore` (Data Protection), `KeychainTokenStore`, `PrivacyConsents`, `DataExporter` |

`AppModel` (iOS) ist die einzige Stelle, an der UI und Fachlogik zusammenkommen. Alle Regeln
sind in `FitnessCore` und damit ohne Gerät testbar.

```
SwiftUI-Views ──► AppModel (@MainActor, @Observable)
                    │
                    ├── AppRepository ── LocalStore (JSON-Dateien, atomar, .bak)
                    ├── PlanGenerator / ProgressionEngine / TrainingAssistant
                    ├── WorkoutRun  (jede Aktion → sofort gespeichert)
                    ├── SyncCoordinator ──► VitalDataProvider
                    │                         ├── HealthKitVitalProvider (Apple, Garmin via Health)
                    │                         ├── WhoopProvider ─► WhoopClient ─► Token-Broker / WHOOP API v2
                    │                         └── GarminDirectProvider (deaktiviert)
                    └── WatchWorkoutBridge ◄──► Apple Watch (Mirroring + WatchConnectivity)
```

## Datenmodell

Alle Entitäten sind `Codable`-Werttypen mit eindeutigen Identifikatoren.

| Entität | Schlüssel | Beziehungen / Indizes |
|---|---|---|
| `UserProfile` | `id: UUID` | enthält `PhysicalRestriction[]`, `HealthSettings`, `ProgramStatus`, `PrivacyConsents` |
| `DeviceConnection` | `kind: IntegrationKind` (eindeutig) | 1:1 zu `SyncState` |
| `Exercise` | `id: String` (Slug, stabil) | `alternatives`, `regressionId`, `progressionId` → `Exercise.id` (beim Laden validiert); Index `[id: Position]` |
| `TrainingPlan` | `id: UUID` | `PlanWeek[]` → `PlannedWorkout(id)` → `PlannedExercise(id, exerciseId)`; ältere Pläne in `planArchive` |
| `WorkoutSession` | `id: UUID` | `plannedWorkoutId` → `PlannedWorkout`; `SessionExercise[]` → `ExerciseSet[]`; Index `[id: Position]` |
| `ExerciseSet` | `id: UUID` | `sessionId`, `exerciseId` |
| `VitalSample` | `id: UUID` | `sessionId?`; Duplikatschlüssel `channel+type+sourceRecordId` bzw. `source+type+start+value` (Hash-Index beim Einlesen) |
| `RecoveryMetric` | `source + dayKey` | aus `VitalSample` je Quelle und Tag verdichtet (nie quellenübergreifend) |
| `SyncState` | `kind` | Cursor, `syncedUntil`, letzter Fehler, Fehlerzähler |
| `PainReport`, `ReadinessCheckIn`, `Recommendation` | `id` | Protokolle für Assistent und Nachvollziehbarkeit |
| `WorkoutRun` | – | laufende Einheit; nach jeder Aktion in `activeRun.json` gesichert |

Pflichtfelder eines Vitaldatensatzes (Auftrag Kap. 11): `type`, `value`, `unit`, `start/end`,
`source` (Originalquelle), `channel` (Übertragungsweg), `deviceId`, `sessionId`, `quality`
(`measured`, `derived`, `estimated`, `calibrating`, `unscored`, `userEntered`, `demo`).

### Warum JSON-Dateien statt SwiftData/Core Data?

* Datenmenge einer Person ist klein (Jahre an Training ≈ wenige MB).
* Identisches Verhalten unter iOS, watchOS, macOS **und Linux** → die gesamte Persistenz inkl.
  Wiederherstellung und Migration ist automatisiert getestet.
* Export ist trivial und verlustfrei; Migrationen sind explizit (`SchemaMigration`) und testbar.
* Der Zugriff läuft ausschließlich über `AppRepository` – ein späterer Wechsel auf SwiftData
  ist ohne Änderungen an UI oder Fachlogik möglich.

### Migrationen

`meta.json` enthält `schemaVersion`. Beim Start führt `AppRepository` registrierte
`SchemaMigration`s der Reihe nach aus; fehlende Migrationen oder Daten einer neueren
App-Version führen zu einem sichtbaren Fehler statt zu Datenverlust.

## Schnittstellen (Auszug)

```swift
protocol VitalDataProvider: Sendable {
    var kind: IntegrationKind { get }
    func fetch(since: Date?, cursor: String?, until: Date) async throws -> ProviderBatch
}
protocol HTTPClient: Sendable { func send(_ r: URLRequest) async throws -> (Data, HTTPURLResponse) }
protocol TokenStore: Sendable { loadToken / saveToken / deleteToken }
enum WatchMessage: Codable { heartRate, workoutState, command, context, summary, ack }
```

Neue Wearables werden durch einen weiteren `VitalDataProvider` angebunden – Harmonisierung,
Prioritäten, Diagramme und Assistent funktionieren dann ohne weitere Änderungen.

## Apple Watch ↔ iPhone

1. iPhone startet das Training → `HKHealthStore.startWatchApp(with:)`.
2. Watch erstellt `HKWorkoutSession` + `HKLiveWorkoutBuilder` (`HKLiveWorkoutDataSource`) und
   ruft `startMirroringToCompanionDevice()` auf.
3. iPhone erhält die gespiegelte Sitzung über `workoutSessionMirroringStartHandler`.
4. Puls: Watch → `sendToRemoteWorkoutSession(data:)` (nummerierte `WatchEnvelope`s); iPhone
   verwirft Doppelte über `MessageInbox`. Zeitstempel = Messzeitpunkt, nicht Empfangszeit;
   Mittelwerte zeitgewichtet; Lücken > 30 s werden als Messlücke ausgewiesen.
5. Verbindungsverlust: Watch zeichnet weiter auf und puffert lokal (`active-workout-buffer.json`).
6. Ende: Zusammenfassung mit vollständigem Pulsverlauf per `transferUserInfo` (garantierte
   Zustellung). Speichern in Apple Health nur mit Zustimmung (`finishWorkout`), sonst `discardWorkout`.
7. Absturz/Neustart der Watch-App: `handleActiveWorkoutRecovery` → `recoverActiveWorkoutSession()`.

## Externe Abhängigkeiten

Keine Drittanbieter-Bibliotheken. Verwendet werden ausschließlich Apple-Frameworks
(Foundation, SwiftUI, Charts, HealthKit, WatchConnectivity, WatchKit, AuthenticationServices,
Security, UserNotifications). Entwicklungswerkzeuge: Xcode ≥ 15, optional XcodeGen.
Serverseitig optional: Cloudflare Worker (oder jede andere HTTPS-Funktion) als WHOOP-Token-Broker.

## Vorgesehene Erweiterungen (architektonisch vorbereitet)

| Erweiterung | Ansatzpunkt |
|---|---|
| Reisemodus (nur TRX/Eigengewicht, 15–20 min) | `UserProfile.kettlebellsKg = []` bzw. `hasTRX` → `SafetyFilter` ersetzt automatisch; `sessionMinutes` steuert `fitToTimeBudget`. Eigene `DayTemplates` ergänzen. |
| Golf-/Tennismodus | weitere `WorkoutDayType`/`DayTemplates` mit Anti-Rotation, BWS-Rotation, Balance (Übungen bereits vorhanden: Pallof Press, Rotational Row, Open Book, Seitausfallschritt …) |
| Weitere Wearables | neuer `VitalDataProvider` + `DataSource`-Fall + Prioritäten |
| KI-Assistent | gleiche Eingaben wie `AssistantContext`; Ausgabe als `Recommendation` mit `RuleHit`s. Übermittlung nur mit gesonderter Einwilligung (`PrivacyConsents.sendDataToAIServices`). |
| Cloud-Sync | `PrivacyConsents.cloudSync`; Repository-Schicht austauschbar |
