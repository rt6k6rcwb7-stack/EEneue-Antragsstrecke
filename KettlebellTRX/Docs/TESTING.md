# Tests

## Automatisierte Tests (`swift test`)

70 Tests in `Tests/FitnessCoreTests`, laufen unter macOS und Linux sowie in der CI
(`.github/workflows/kettlebell-trx.yml`).

| Bereich (Auftrag) | Tests |
|---|---|
| Trainingslogik | 8-Wochen-Struktur, Phasen (Sätze/Wdh./Gewicht), Zeitbudget, Überkopf-/Swing-Regeln, Einschränkungen, Beschwerden, fehlende Ausrüstung, Termine, Gewichtswahl, Progression (Steigerung, Sperren, Reduktion, manuelle Werte bleiben) |
| Timer / Player | Satzabschluss, Pausenstart/-ende, Pause während Satzpause (Restzeit bleibt), Dauer ohne Pausen, ±15 s, Überspringen, Ersetzen (auch nach begonnenem Satz), Gewicht/Wdh. ändern, vorzeitiges Ende, vollständiger Durchlauf, Intensitätsfaktor |
| Datenpersistenz | Rundreise aller Sammlungen, beschädigte Datei → Sicherung, exakte Wiederherstellung eines laufenden Trainings, Migrationen, neuere Schemata, Beispieldaten löschen, alles löschen, Export JSON/CSV |
| Datenharmonisierung | Mehrfach-Sync ohne Duplikate, Health-Kopien direkt angebundener Quellen, unplausible Werte, Prioritäten/Deaktivierung, HRV-Methoden getrennt, Lücken bleiben leer, Schlafaggregation, Warnhinweise |
| Synchronisierungsfehler | Netzwerkfehler sichtbar + Zähler, lokale Daten unberührt, andere Quellen laufen weiter, Backoff |
| Geräteverbindungsstatus | Autorisierungsfehler → Status „Fehler“, deaktivierte Quellen übersprungen, Garmin direkt „nicht verfügbar“, Status „verbunden“ nach Erfolg |
| Herzfrequenz | zeitgewichteter Mittelwert bei unregelmäßigen Intervallen, Lücken, verspätete/doppelte/unplausible Werte, „veraltet“-Erkennung, Zonen |
| WHOOP | Dekodierung v2, nur bewertete Werte, Kalibrierung, Schlaf ohne Nickerchen, Autorisierungs-URL und `state`-Prüfung, Paginierung, 401 → Refresh → Wiederholung, 429, fehlendes Token, Trennen |
| HealthKit-Mapping / Garmin | Quellenerkennung, Schlafphasen, Energie als Schätzung, Garmin-Verfügbarkeitsbericht |
| Watch-Protokoll | Outbox/Bestätigung, Duplikate über zwei Kanäle, Begrenzung, Kodierung |
| Assistent | alle Sicherheitsregeln, Rückkehr nach Fieber trotz bester Recovery, gute Recovery übersteuert keine Belastungsregel, Vitalregeln nur gleiche Quelle, Kombination, fehlende Daten |
| Familie / Ersteinrichtung | Neuinstallation verlangt Einrichtung, Plan aus Profil (eigene Tage/Kettlebells), neutrales Vorbelegungsprofil, Gesundheits-Check setzt vorsichtige Einstellungen, Löschen startet Einrichtung neu |
| Bibliothek / Animation | ≥ 40 vollständige Übungen, Kategorien, Verweise, Erweiterungsdatei, Bodenkontakt aller Animationen |

```bash
cd KettlebellTRX && swift test
```

## Build-Prüfung der Apps

Die CI erzeugt das Xcode-Projekt (XcodeGen) und baut iOS- und Watch-App ohne Signatur für den
Simulator (`macos-15`). Lokal: `xcodegen generate && xcodebuild -scheme KettlebellTRX -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`.

## Manueller Testplan auf echten Geräten (noch durchzuführen)

| # | Szenario | Erwartung |
|---|---|---|
| 1 | Erststart, Profil prüfen, Apple Health verbinden | Berechtigungsdialog, Status „Verbunden“ |
| 2 | Training starten (iPhone) | Watch-App öffnet sich, Puls erscheint auf iPhone innerhalb weniger Sekunden |
| 3 | Satz erledigen, Pause ±15 s, überspringen, ersetzen, Gewicht ändern | Werte korrekt im Satzprotokoll |
| 4 | iPhone sperren während Satzpause | Benachrichtigung „Pause vorbei“ |
| 5 | App während des Trainings beenden (App-Umschalter) und neu öffnen | Training läuft an gleicher Stelle weiter |
| 6 | Bluetooth am iPhone 2 min ausschalten | Watch zeigt „zeichnet lokal auf“; nach Wiederverbindung Puls wieder live; nach Ende vollständiger Pulsverlauf in der Einheit |
| 7 | Watch-App abstürzen lassen/neu starten während Training | Sitzung wird wiederhergestellt |
| 8 | Training ohne Watch | Puls „nicht verfügbar“, Training funktioniert vollständig |
| 9 | Flugmodus, komplettes Training | alles offline nutzbar, keine Fehlermeldung außer Sync |
| 10 | Speichern in Apple Health an/aus | Workout erscheint nur bei Zustimmung in Health |
| 11 | Garmin-Datenarten prüfen | Liste zeigt tatsächlich übertragene Datenarten der S70 |
| 12 | WHOOP verbinden, synchronisieren, widerrufen | Recovery/HRV/Schlaf sichtbar; Widerruf löscht Token |
| 13 | Export teilen, alle Daten löschen | Dateien vollständig; danach leere App mit neuem Plan |
| 14 | VoiceOver, große Schrift | Player bedienbar, Werte vorgelesen |
