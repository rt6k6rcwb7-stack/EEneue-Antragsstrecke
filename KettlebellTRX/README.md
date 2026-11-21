# Kettlebell & TRX Training

Persönliche Fitness- und Vitaldaten-App für iPhone, iPad und Apple Watch: ein periodisierter
8-Wochen-Plan mit Kettlebell, TRX und Eigengewicht, ein interaktiver Trainingsplayer mit
Live-Puls, Vitaldaten aus Apple Health, Garmin (über Apple Health) und WHOOP sowie ein
regelbasierter, konservativer Trainingsassistent.

> **Kein Medizinprodukt.** Die App stellt keine Diagnosen und leitet aus Vitaldaten keine
> Trainingsfreigabe ab. Bei Warnsymptomen weist sie auf ärztliche Abklärung hin.

## Stand dieser Version (1.0, November 2026)

| Bereich | Umsetzung | Geprüft |
|---|---|---|
| Kernlogik `FitnessCore` (Plan, Progression, Player-Zustand, Timer, Harmonisierung, Assistent, Persistenz, Export, Sync, WHOOP-Client, HealthKit-Mapping, Watch-Protokoll) | vollständig | **66 automatisierte Tests, grün** (Linux, Swift 6.0.3) |
| Übungsbibliothek | 58 Übungen, eigene animierte Darstellungen | per Test auf Vollständigkeit geprüft |
| iOS-/iPadOS-App (SwiftUI) | Dashboard, Plan, Training/Player, Bibliothek, Fortschritt, Einstellungen | Syntax geprüft; **Kompilierung über CI auf macOS** (siehe unten); **nicht auf echtem Gerät getestet** |
| watchOS-App | Workout-Session, Live-Puls, Mirroring, Wiederherstellung | **nicht auf echter Apple Watch getestet** |
| Apple Health | Lesen (Ruhepuls, HRV, Schlaf, Aktivität, Workouts), Speichern nach Zustimmung | **nicht auf Gerät getestet** |
| Garmin Approach S70 | Stufe 1: über Apple Health inkl. Verfügbarkeitsprüfung. Stufe 2 (direkte API): bewusst **nicht aktiviert** | Mapping getestet; echte Garmin-Daten nicht geprüft |
| WHOOP API v2 | OAuth 2.0 über eigenen Token-Broker, Recovery/Schlaf/Zyklen/Workouts, Paginierung, Token-Erneuerung | mit simulierten API-Antworten getestet; **ohne echten WHOOP-Zugang nicht real getestet** |

Details: [Docs/OPEN_ITEMS.md](Docs/OPEN_ITEMS.md).

## Schnellstart

```bash
cd KettlebellTRX
swift test                       # Kernlogik testen (macOS oder Linux)
swift run kbtrx-plan             # 8-Wochen-Plan im Terminal anzeigen
swift run kbtrx-plan woche 5     # Detail einer Woche
swift run kbtrx-plan simulation  # simulierte Einheit + Assistent (Beispieldaten)

brew install xcodegen && xcodegen generate
open KettlebellTRX.xcodeproj     # App auf iPhone + Apple Watch installieren
```

Ausführlich: [Docs/INSTALLATION.md](Docs/INSTALLATION.md)

## Dokumentation

| Dokument | Inhalt |
|---|---|
| [ARCHITECTURE.md](Docs/ARCHITECTURE.md) | Projektstruktur, Komponenten, Datenmodell, Schnittstellen, Abhängigkeiten |
| [INSTALLATION.md](Docs/INSTALLATION.md) | Installation mit Xcode auf iPhone und Apple Watch, TestFlight |
| [INTEGRATIONS.md](Docs/INTEGRATIONS.md) | Apple HealthKit, Garmin (Prüfergebnis), WHOOP (OAuth, Broker, Endpunkte) |
| [TRAINING.md](Docs/TRAINING.md) | Trainingskonzept, Periodisierung, Sicherheitsregeln der Übungsauswahl |
| [ASSISTANT_RULES.md](Docs/ASSISTANT_RULES.md) | Alle Entscheidungsregeln des Assistenten |
| [EXERCISES.md](Docs/EXERCISES.md) | Übungsbibliothek erweitern |
| [PRIVACY.md](Docs/PRIVACY.md) | Datenschutz, DSGVO, Datensicherheit |
| [TESTING.md](Docs/TESTING.md) | Automatisierte Tests und Testplan für echte Geräte |
| [OPEN_ITEMS.md](Docs/OPEN_ITEMS.md) | Offene Funktionen und nicht real getestete Teile |
