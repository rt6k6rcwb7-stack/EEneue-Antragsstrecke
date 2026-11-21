# Offene Punkte und nicht real getestete Funktionen

Stand: Version 1.0, November 2026. Entwickelt in einer Linux-Umgebung ohne Mac, ohne
Apple-Geräte, ohne WHOOP- und Garmin-Zugang.

## Nicht real getestet (Hardware/Zugang fehlte)

| Funktion | Grund | Was geprüft ist |
|---|---|---|
| iOS-/watchOS-UI auf Geräten | kein Mac/iPhone/Watch | Syntax; Kompilierung über CI (macOS) |
| HealthKit lesen/schreiben | kein Gerät | Mapping und Quellenerkennung per Test |
| Workout Mirroring, Live-Puls, Verbindungsabbruch, Wiederherstellung auf der Watch | keine Watch | Nachrichtenprotokoll, Duplikat-/Lückenlogik per Test |
| Garmin-Daten über Apple Health (Approach S70) | kein Gerät | Mapping; welche Datenarten real ankommen, zeigt die Prüffunktion in der App |
| WHOOP OAuth und Datenabruf | kein Developer-Zugang | Client gegen nachgebildete v2-Antworten |
| WHOOP-Token-Broker | nicht bereitgestellt | JavaScript-Syntax |
| Benachrichtigung zum Pausenende, Haptik, VoiceOver | kein Gerät | – |

Bitte den Testplan in [TESTING.md](TESTING.md) auf echten Geräten durchführen.

## Bewusst nicht umgesetzt / offen

* **Direkte Garmin-Anbindung**: erst nach bestätigtem Zugang zur Garmin Personal API (siehe INTEGRATIONS.md).
* **WHOOP-Webhooks**: erfordern Server-Infrastruktur, in V1 Polling bei App-Start/Pull-to-Refresh.
* **Hintergrund-Synchronisierung** (BGAppRefreshTask): nicht umgesetzt, Sync beim Öffnen der App.
* **Demonstrationsvideos**: Feld `mediaFile` vorhanden, Wiedergabe im Player noch nicht verdrahtet.
  Stattdessen 43 eigene animierte Darstellungen.
* **iPad-Layout**: läuft, nutzt aber noch dasselbe Layout wie das iPhone (kein Split-View).
* **Satz-Erfassung auf der Watch**: die Watch zeigt Übung/Satz/Pause und steuert Pause/Ende;
  Sätze werden am iPhone bestätigt.
* **Erweiterungen** (Reisemodus, Golf-/Tennismodus, weitere Wearables, KI): architektonisch
  vorbereitet (ARCHITECTURE.md), nicht umgesetzt.
* **Lokalisierung**: Oberfläche nur Deutsch (englische Übungsnamen vorhanden).
* **Dauer Wochen 1–2/8**: geschätzt ca. 26–30 min, also am unteren Rand der gewünschten 30–40 min
  (Technik- bzw. Entlastungsphase mit 2 Sätzen). Bei Bedarf Sätze/Pausen im Plan erhöhen.

## Hinweise

* Die Übungsbeschreibungen und Regeln sind sportwissenschaftlich begründet, ersetzen aber keine
  individuelle Beratung durch Ärztin/Arzt oder Physiotherapie – insbesondere nicht bei Herz-Kreislauf-,
  Wirbelsäulen- oder Schulterbeschwerden.
* Vor dem ersten Einsatz von Swings die Hüftbeuge-Technik (Kreuzheben) sicher beherrschen und die
  Technikfreigabe im Profil bewusst setzen.
